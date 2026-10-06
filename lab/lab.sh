#!/bin/bash
# A lab on this machine, without root: two qemu VMs running Debian 13.
#
#   dc   the domain controller (no display)
#   pc1  a workstation with a desktop, shown in a window (or over VNC)
#
# They share a private network, 10.10.0.0/24 (dc is 10.10.0.1, pc1
# 10.10.0.21), and each reaches the Internet through qemu's user network.
#
# Usage: lab/lab.sh up | deploy | ssh <vm> | screenshot <vm> <file.png>
#                   | status | down | destroy
set -euo pipefail

LAB_DIR=${LAB_DIR:-$HOME/.cache/krb-demo-lab}
IMAGE_URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
HERE=$(cd "$(dirname "$0")" && pwd)
VMS=(dc pc1)

# name -> RAM (MB), lan address, SSH port on the host
declare -A RAM=([dc]=4096 [pc1]=3072)
declare -A LAN=([dc]=10.10.0.1 [pc1]=10.10.0.21)
declare -A SSH_PORT=([dc]=2222 [pc1]=2223)
# The private network is a UDP tunnel between the two VMs.
declare -A LAN_LOCAL=([dc]=10001 [pc1]=10002)
declare -A LAN_REMOTE=([dc]=10002 [pc1]=10001)
declare -A MAC_ID=([dc]=01 [pc1]=21)

die() { echo "lab: $*" >&2; exit 1; }
pidfile() { echo "$LAB_DIR/$1.pid"; }
pid() { cat "$(pidfile "$1")" 2>/dev/null; }

# A pidfile can outlive its VM (a reboot of this machine): the process must
# also be this VM's qemu.
running() {
  local p
  p=$(pid "$1") || return 1
  [ -n "$p" ] && tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q "qemu-system.* -name $1 "
}

stop() {
  local vm=$1
  running "$vm" || return 0
  kill "$(pid "$vm")"
  for _ in $(seq 1 30); do running "$vm" || return 0; sleep 1; done
  die "$vm does not stop"
}

check_vm() {
  [[ " ${VMS[*]} " == *" $1 "* ]] || die "unknown VM '$1' (${VMS[*]})"
}

image() {
  # qemu's monitor sockets live there: Unix socket paths stop at 107 bytes.
  [ ${#LAB_DIR} -le 90 ] || die "LAB_DIR is too long for a Unix socket path: $LAB_DIR"
  mkdir -p "$LAB_DIR"
  if [ ! -f "$LAB_DIR/debian-13.qcow2" ]; then
    echo "lab: downloading the Debian 13 cloud image"
    curl -fL --progress-bar -o "$LAB_DIR/debian-13.qcow2.part" "$IMAGE_URL"
    mv "$LAB_DIR/debian-13.qcow2.part" "$LAB_DIR/debian-13.qcow2"
  fi
  [ -f "$LAB_DIR/id_lab" ] || ssh-keygen -q -t ed25519 -N '' -C krb-demo-lab -f "$LAB_DIR/id_lab"
}

# A disk on top of the cloud image, and the cloud-init seed that sets the
# host name, the SSH key and the private address.
prepare() {
  local vm=$1 dir="$LAB_DIR/$1"
  [ -f "$dir/disk.qcow2" ] && return
  mkdir -p "$dir"
  qemu-img create -q -f qcow2 -b "$LAB_DIR/debian-13.qcow2" -F qcow2 "$dir/disk.qcow2" 20G
  cat >"$dir/user-data" <<EOF
#cloud-config
hostname: $vm
users:
  - name: debian
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$LAB_DIR/id_lab.pub")
EOF
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$vm" "$vm" >"$dir/meta-data"
  cat >"$dir/network-config" <<EOF
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
EOF
  (cd "$dir" && genisoimage -quiet -output seed.iso -volid cidata -joliet -rock \
    user-data meta-data network-config)
}

start() {
  local vm=$1 dir="$LAB_DIR/$1" fwd display
  running "$vm" && { echo "lab: $vm already runs"; return; }
  fwd="hostfwd=tcp:127.0.0.1:${SSH_PORT[$vm]}-:22"
  if [ "$vm" = dc ]; then
    # The services, for a browser on this machine. Ports under 1024 need
    # ip_unprivileged_port_start lowered; without them the lab still works
    # from pc1.
    if [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)" -le 80 ]; then
      fwd+=",hostfwd=tcp:127.0.0.1:80-:80,hostfwd=tcp:127.0.0.1:443-:443"
      fwd+=",hostfwd=tcp:127.0.0.1:88-:88,hostfwd=udp:127.0.0.1:88-:88"
      fwd+=",hostfwd=tcp:127.0.0.1:749-:749"
    else
      echo "lab: ports 80/443/88 not forwarded to this machine (see docs/lab.md)"
    fi
    display=(-display none)
  elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ "${LAB_DISPLAY:-gtk}" = gtk ]; then
    display=(-display gtk,zoom-to-fit=on -vga std -device qemu-xhci -device usb-tablet)
  else
    display=(-display none -vnc 127.0.0.1:1 -vga std -device qemu-xhci -device usb-tablet)
    echo "lab: pc1's screen is on VNC, 127.0.0.1:5901"
  fi
  setsid qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m "${RAM[$vm]}" \
    -name "$vm" -pidfile "$(pidfile "$vm")" \
    -drive "file=$dir/disk.qcow2,if=virtio" \
    -drive "file=$dir/seed.iso,media=cdrom" \
    -netdev "user,id=wan,$fwd" \
    -device "virtio-net-pci,netdev=wan,mac=52:54:00:12:00:${MAC_ID[$vm]}" \
    -netdev "dgram,id=lan,local.type=inet,local.host=127.0.0.1,local.port=${LAN_LOCAL[$vm]},remote.type=inet,remote.host=127.0.0.1,remote.port=${LAN_REMOTE[$vm]}" \
    -device "virtio-net-pci,netdev=lan,mac=52:54:00:10:00:${MAC_ID[$vm]}" \
    -monitor "unix:$dir/monitor,server,nowait" \
    -serial "file:$dir/serial.log" \
    "${display[@]}" >"$dir/qemu.log" 2>&1 </dev/null &
  # qemu exits at once when it cannot start: a port already taken, say.
  sleep 2
  running "$vm" || die "$vm did not start: $(cat "$dir/qemu.log")"
  echo "lab: $vm started"
}

# The lab key only: never the keys of an agent, which would prompt for their
# passphrase.
set_ssh_opts() {
  [ -f "$LAB_DIR/id_lab" ] || die "no lab key in $LAB_DIR: run lab/lab.sh up first"
  SSH_OPTS=(-i "$LAB_DIR/id_lab" -o IdentitiesOnly=yes -o IdentityAgent=none
    -p "${SSH_PORT[$1]}" -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
}

wait_ssh() {
  local vm=$1
  set_ssh_opts "$vm"
  for _ in $(seq 1 60); do
    ssh "${SSH_OPTS[@]}" -o ConnectTimeout=3 debian@127.0.0.1 \
      'cloud-init status --wait >/dev/null' 2>/dev/null && return
    sleep 3
  done
  die "$vm does not answer on SSH (see $LAB_DIR/$vm/serial.log)"
}

case "${1:-}" in
up)
  command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86 is missing"
  command -v genisoimage >/dev/null || die "genisoimage is missing"
  [ -w /dev/kvm ] || die "/dev/kvm is not writable: add yourself to the kvm group"
  image
  for vm in "${VMS[@]}"; do prepare "$vm"; start "$vm"; done
  for vm in "${VMS[@]}"; do wait_ssh "$vm"; echo "lab: $vm is up"; done
  ;;
deploy)
  shift
  # The desktop gets this machine's keyboard layout.
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
  echo "screendump $LAB_DIR/$vm/screen.ppm" | socat - "UNIX-CONNECT:$LAB_DIR/$vm/monitor" >/dev/null
  sleep 1
  convert "$LAB_DIR/$vm/screen.ppm" "$out"
  ;;
status)
  for vm in "${VMS[@]}"; do
    if running "$vm"; then echo "$vm: running"; else echo "$vm: stopped"; fi
  done
  ;;
down)
  for vm in "${VMS[@]}"; do
    if running "$vm"; then
      echo system_powerdown | socat - "UNIX-CONNECT:$LAB_DIR/$vm/monitor" >/dev/null
      echo "lab: $vm stopping"
    fi
  done
  ;;
destroy)
  for vm in "${VMS[@]}"; do
    stop "$vm"
    rm -rf "${LAB_DIR:?}/$vm" "$(pidfile "$vm")"
  done
  echo "lab: VMs destroyed (the cloud image stays in $LAB_DIR)"
  ;;
*)
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
