#!/bin/bash
# The lab of lab.sh, on VirtualBox (Linux host): three VMs from the Debian
# cloud images, no KVM needed.
#
#   krb-coruscant  the domain controller, Debian 13 (no display)
#   krb-kamino     the Rudder server, Debian 13 (no display)
#   krb-tatooine   a workstation with a desktop, Debian 13
#
# Each has two network cards: NAT (Internet, and SSH from this machine on
# ports 2222-2224) and the internal network "starwars", 10.10.0.0/24
# (coruscant is 10.10.0.1, kamino 10.10.0.2, tatooine 10.10.0.21). The VMs are
# named krb-*, so that they never meet machines of your own. It shares the
# images, the SSH key and the inventory with lab.sh: lab/check.sh works with
# LAB=lab/vboxlab.sh.
#
# Usage: lab/vboxlab.sh up | deploy | ssh <vm> | screenshot <vm> <file.png>
#                       | status | down | destroy
set -euo pipefail

LAB_DIR=${LAB_DIR:-$HOME/.cache/krb-demo-lab}
HERE=$(cd "$(dirname "$0")" && pwd)
VMS=(coruscant kamino tatooine)
INTNET=starwars

declare -A RELEASE=([coruscant]=13 [tatooine]=13 [kamino]=13)
declare -A CODENAME=([12]=bookworm [13]=trixie)
image_url() { echo "https://cloud.debian.org/images/cloud/${CODENAME[$1]}/latest/debian-$1-genericcloud-amd64.qcow2"; }
declare -A RAM=([coruscant]=4096 [kamino]=3072 [tatooine]=3072)
declare -A LAN=([coruscant]=10.10.0.1 [kamino]=10.10.0.2 [tatooine]=10.10.0.21)
declare -A SSH_PORT=([coruscant]=2222 [tatooine]=2223 [kamino]=2224)
declare -A MAC_ID=([coruscant]=01 [kamino]=02 [tatooine]=21)

die() { echo "vboxlab: $*" >&2; exit 1; }
vbox() { VBoxManage "$@"; }
name() { echo "krb-$1"; }
exists() { vbox list vms | grep -q "^\"$(name "$1")\" "; }
running() { vbox list runningvms | grep -q "^\"$(name "$1")\" "; }

check_vm() {
  [[ " ${VMS[*]} " == *" $1 "* ]] || die "unknown VM '$1' (${VMS[*]})"
}

image() {
  mkdir -p "$LAB_DIR"
  local rel
  for rel in $(printf '%s\n' "${RELEASE[@]}" | sort -u); do
    if [ ! -f "$LAB_DIR/debian-$rel.qcow2" ]; then
      echo "vboxlab: downloading the Debian $rel cloud image"
      curl -fL --progress-bar -o "$LAB_DIR/debian-$rel.qcow2.part" "$(image_url "$rel")"
      mv "$LAB_DIR/debian-$rel.qcow2.part" "$LAB_DIR/debian-$rel.qcow2"
    fi
  done
  [ -f "$LAB_DIR/id_lab" ] || ssh-keygen -q -t ed25519 -N '' -C krb-demo-lab -f "$LAB_DIR/id_lab"
}

# The VM, its disk (the cloud image converted, 20 GB) and the cloud-init seed
# that sets the host name, the SSH key and the private address. The cards'
# MAC addresses are the ones lab.sh uses, which the seed matches.
create() {
  local vm=$1 n dir="$LAB_DIR/vbox/$1"
  exists "$vm" && return
  mkdir -p "$dir"
  qemu-img convert -f qcow2 -O vdi "$LAB_DIR/debian-${RELEASE[$vm]}.qcow2" "$dir/disk.vdi"
  vbox modifymedium disk "$dir/disk.vdi" --resize 20480

  cat >"$dir/user-data" <<EOT
#cloud-config
hostname: $vm
users:
  - name: debian
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$LAB_DIR/id_lab.pub")
EOT
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$vm" "$vm" >"$dir/meta-data"
  cat >"$dir/network-config" <<EOT
version: 2
ethernets:
  wan:
    match:
      macaddress: "52:54:00:12:00:${MAC_ID[$vm]}"
    dhcp4: true
  lan:
    match:
      macaddress: "52:54:00:10:00:${MAC_ID[$vm]}"
    addresses: [${LAN[$vm]}/24]
EOT
  (cd "$dir" && genisoimage -quiet -output seed.iso -volid cidata -joliet -rock \
    user-data meta-data network-config)

  n=$(name "$vm")
  vbox createvm --name "$n" --ostype "Debian_64" --register >/dev/null
  vbox modifyvm "$n" --memory "${RAM[$vm]}" --cpus 2 --ioapic on --rtcuseutc on \
    --graphicscontroller vmsvga --vram "$([ "$vm" = tatooine ] && echo 64 || echo 16)" \
    --nic1 nat --nictype1 virtio --macaddress1 "5254001200${MAC_ID[$vm]}" \
    --nic2 intnet --intnet2 "$INTNET" --nictype2 virtio --macaddress2 "5254001000${MAC_ID[$vm]}" \
    --uart1 0x3F8 4 --uartmode1 file "$dir/serial.log"
  vbox modifyvm "$n" --natpf1 "ssh,tcp,127.0.0.1,${SSH_PORT[$vm]},,22"
  if [ "$vm" = coruscant ]; then
    # The services, for a browser on this machine. Ports under 1024 need
    # ip_unprivileged_port_start lowered; without them the lab still works
    # from tatooine.
    if [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)" -le 80 ]; then
      vbox modifyvm "$n" --natpf1 "http,tcp,127.0.0.1,80,,80" \
        --natpf1 "https,tcp,127.0.0.1,443,,443" \
        --natpf1 "krb,tcp,127.0.0.1,88,,88" --natpf1 "krbudp,udp,127.0.0.1,88,,88" \
        --natpf1 "kadmin,tcp,127.0.0.1,749,,749"
    else
      echo "vboxlab: ports 80/443/88 not forwarded to this machine (see docs/lab.md)"
    fi
  fi
  vbox storagectl "$n" --name SATA --add sata --controller IntelAhci
  vbox storageattach "$n" --storagectl SATA --port 0 --device 0 --type hdd --medium "$dir/disk.vdi"
  vbox storageattach "$n" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$dir/seed.iso"
  vbox modifyvm "$n" --boot1 disk --boot2 dvd
}

start() {
  local vm=$1 type=headless
  running "$vm" && { echo "vboxlab: $vm already runs"; return; }
  if [ "$vm" = tatooine ]; then
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      type=gui
    else
      echo "vboxlab: no graphical session: tatooine runs headless (VBoxManage controlvm krb-tatooine screenshotpng)"
    fi
  fi
  vbox startvm "$(name "$vm")" --type "$type" >/dev/null
  echo "vboxlab: $vm started"
}

set_ssh_opts() {
  [ -f "$LAB_DIR/id_lab" ] || die "no lab key in $LAB_DIR: run lab/vboxlab.sh up first"
  SSH_OPTS=(-i "$LAB_DIR/id_lab" -o IdentitiesOnly=yes -o IdentityAgent=none
    -p "${SSH_PORT[$1]}" -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
}

wait_ssh() {
  local vm=$1
  set_ssh_opts "$vm"
  for _ in $(seq 1 100); do
    ssh "${SSH_OPTS[@]}" -o ConnectTimeout=3 debian@127.0.0.1 \
      'cloud-init status --wait >/dev/null' 2>/dev/null && return
    sleep 3
  done
  die "$vm does not answer on SSH (see $LAB_DIR/vbox/$vm/serial.log)"
}

case "${1:-}" in
up)
  for c in VBoxManage qemu-img genisoimage curl; do
    command -v "$c" >/dev/null || die "$c is missing"
  done
  image
  for vm in "${VMS[@]}"; do create "$vm"; start "$vm"; done
  for vm in "${VMS[@]}"; do wait_ssh "$vm"; echo "vboxlab: $vm is up"; done
  ;;
deploy)
  shift
  layout=$(. /etc/default/keyboard 2>/dev/null && echo "${XKBLAYOUT:-us}") || layout=us
  variant=$(. /etc/default/keyboard 2>/dev/null && echo "${XKBVARIANT:-}") || variant=
  cd "$HERE/.."
  LAB_DIR=$LAB_DIR ansible-playbook -i lab/inventory.yml site.yml \
    -e "sw_keyboard_layout=${layout%%,*} sw_keyboard_variant=${variant%%,*}" "$@"
  ;;
ssh)
  vm=${2:?which VM?}
  check_vm "$vm"
  shift 2
  set_ssh_opts "$vm"
  exec ssh "${SSH_OPTS[@]}" debian@127.0.0.1 "$@"
  ;;
screenshot)
  vm=${2:?which VM?}
  out=${3:?output file?}
  check_vm "$vm"
  running "$vm" || die "$vm is not running"
  vbox controlvm "$(name "$vm")" screenshotpng "$out"
  ;;
status)
  for vm in "${VMS[@]}"; do
    if running "$vm"; then echo "$vm: running"; else echo "$vm: stopped"; fi
  done
  ;;
down)
  for vm in "${VMS[@]}"; do
    if running "$vm"; then
      vbox controlvm "$(name "$vm")" acpipowerbutton
      echo "vboxlab: $vm stopping"
    fi
  done
  ;;
destroy)
  for vm in "${VMS[@]}"; do
    if running "$vm"; then vbox controlvm "$(name "$vm")" poweroff; sleep 2; fi
    if exists "$vm"; then vbox unregistervm "$(name "$vm")" --delete >/dev/null; fi
    rm -rf "${LAB_DIR:?}/vbox/$vm"
  done
  echo "vboxlab: VMs destroyed (the cloud images stay in $LAB_DIR)"
  ;;
*)
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
