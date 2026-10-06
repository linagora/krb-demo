# Lab: the whole demo in two local VMs

`lab/lab.sh` runs the demo on your computer, without root and without
libvirt: two qemu VMs from the Debian 13 cloud image.

| VM | Role | Private address | SSH from your computer |
|---|---|---|---|
| `dc` | Domain controller | `10.10.0.1` | `lab/lab.sh ssh dc` |
| `pc1` | Workstation with a desktop | `10.10.0.21` | `lab/lab.sh ssh pc1` |

The two VMs share a private network, `10.10.0.0/24`, and each reaches the
Internet through qemu's user network.

## Requirements

- KVM: `/dev/kvm` writable (be in the `kvm` group);
- `qemu-system-x86`, `genisoimage`, `socat`, `curl`;
- ImageMagick (`convert`), for `lab/lab.sh screenshot` only;
- Ansible and the collections, as for a [deployment](deployment.md);
- about 7 GB of RAM and 10 GB of disk.

## Running it

```sh
ansible-galaxy collection install -r requirements.yml
lab/lab.sh up        # downloads the cloud image the first time, starts dc and pc1
lab/lab.sh deploy    # runs the playbook against them
```

`deploy` gives pc1's desktop your computer's keyboard layout, read from
`/etc/default/keyboard`. Extra arguments go to `ansible-playbook`, for
instance `lab/lab.sh deploy --limit pc1`.

pc1's screen opens in a window. Log in as any [character](../README.md#who-administers-what-in-the-galaxy),
password = login, and open Firefox. Without a graphical session (or with
`LAB_DISPLAY=vnc`), the screen is on VNC at `127.0.0.1:5901`.

## Commands

| Command | Does |
|---|---|
| `lab/lab.sh up` | Creates the VMs if needed and starts them |
| `lab/lab.sh deploy [ansible args]` | Runs the playbook with `lab/inventory.yml` |
| `lab/lab.sh ssh dc\|pc1 [command]` | SSH as `debian` (sudo without password) |
| `lab/lab.sh screenshot pc1 shot.png` | Saves pc1's screen |
| `lab/lab.sh status` | Tells which VMs run |
| `lab/lab.sh down` | Shuts the VMs down; `up` starts them again |
| `lab/lab.sh destroy` | Deletes the VMs; the cloud image stays |

Everything lives in `~/.cache/krb-demo-lab` (or `$LAB_DIR`): the cloud
image, the lab's SSH key, the VM disks and logs.

## Using the services from your own browser

pc1 is the intended client. To use the portal and the console from your
computer's browser as well, the domain controller must answer on ports 80
and 443 of your computer, which an ordinary user cannot open:

```sh
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80   # until the next reboot
lab/lab.sh down      # wait until lab/lab.sh status shows them stopped
lab/lab.sh up
```

With that, `lab.sh up` forwards 80, 443, 88 and 749 of `127.0.0.1` to dc.
Then, in your `/etc/hosts`, one name per line:

```
127.0.0.1 dc.star.wars
127.0.0.1 auth.star.wars
127.0.0.1 manager.star.wars
127.0.0.1 directory.star.wars
```

and trust the demo CA (`lab/lab.sh ssh dc cat /etc/star-wars/pki/ca.crt > star-wars-ca.crt`).
See [deployment](deployment.md#reaching-the-services-from-another-computer)
for `kinit` from your computer.

Remove those lines from `/etc/hosts` when you are done.

## Troubleshooting

- **`LAB_DIR is too long`**: qemu's monitor sockets live in `$LAB_DIR`, and a
  Unix socket path stops at 107 bytes. Use a shorter directory.
- **`dc does not answer on SSH`**: look at `$LAB_DIR/dc/serial.log`, the VM's
  console, and `$LAB_DIR/dc/qemu.log`.
- **Typing gives the wrong letters on pc1**: the desktop's layout comes from
  your `/etc/default/keyboard` at `deploy` time. Run `deploy` again after
  changing it, or give it: `lab/lab.sh deploy -e "sw_keyboard_layout=fr sw_keyboard_variant=latin9"`.
- **Port forwards missing**: `up` prints it when ports under 1024 cannot be
  opened; the lab still works from pc1.
