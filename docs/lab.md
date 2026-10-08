# Lab: the whole demo in three local VMs

`lab/lab.sh` runs the demo on your computer, without root and without
libvirt: three qemu VMs from the Debian cloud images.

| VM          | Role                       | Private address | SSH from your computer     |
| ----------- | -------------------------- | --------------- | -------------------------- |
| `coruscant` | Domain controller          | `10.10.0.1`     | `lab/lab.sh ssh coruscant` |
| `kamino`    | Rudder server              | `10.10.0.2`     | `lab/lab.sh ssh kamino`    |
| `tatooine`  | Workstation with a desktop | `10.10.0.21`    | `lab/lab.sh ssh tatooine`  |

The three VMs share a private network, `10.10.0.0/24`, and each reaches the
Internet through qemu's user network.

## Requirements

- A Linux computer on x86_64 with KVM: `/dev/kvm` writable (be in the
  `kvm` group). The VMs are amd64 guests run with KVM: neither macOS nor
  an ARM computer will do;
- about 10 GB of RAM for the VMs (4 for Coruscant, 3 each for Kamino and
  Tatooine), on top of your own use, and 15 GB of disk;
- these ports free on `127.0.0.1`: TCP 2222, 2223 and 2224 (SSH to the VMs),
  UDP 10001 (the private network, a multicast group on the loopback), and TCP
  5901 (5900 for Coruscant's) when the screens are on VNC;
- qemu 7.2 or later (Debian 12, Ubuntu 24.04), and the tools, on Debian or
  Ubuntu:

  ```sh
  sudo apt install qemu-system-x86 qemu-utils qemu-system-gui genisoimage socat curl imagemagick
  ```

  `qemu-img` comes from `qemu-utils`, Tatooine's window from `qemu-system-gui`:
  `qemu-system-x86` only recommends them, so name them if you install
  without recommends. ImageMagick is for `lab/lab.sh screenshot` only;

- Ansible, as for a [deployment](deployment.md): ansible-core 2.16 or later
  and the collections. On Debian 13, `sudo apt install ansible` brings
  both; where the packaged one is older (Debian 12 has 2.14),
  `pipx install --include-deps ansible`.

## Running it

```sh
ansible-galaxy collection install -r requirements.yml
lab/lab.sh up        # downloads the cloud image the first time, starts the three VMs
lab/lab.sh deploy    # runs the playbook against them
```

The first `up` downloads the cloud image, about 350 MB; `deploy` then takes
a few minutes, and reboots Tatooine once.

`deploy` gives Tatooine's desktop your computer's keyboard layout, read from
`/etc/default/keyboard`. Extra arguments go to `ansible-playbook`, for
instance `lab/lab.sh deploy --limit tatooine`.

Tatooine's screen opens in a window. Log in as any [character](../README.md#who-administers-what-in-the-galaxy),
password = login, and open Firefox. Without a graphical session (or with
`LAB_DISPLAY=vnc`), the screen is on VNC at `127.0.0.1:5901`.

The services answer on the private network: Tatooine's Firefox reaches them,
your computer's browser does not, even with the names in your
`/etc/hosts`, until you follow the next section.

## On VirtualBox

Without KVM (a virtualized host, a machine where VirtualBox is the
hypervisor), `lab/vboxlab.sh` builds the same three VMs, named `krb-coruscant`,
`krb-kamino` and `krb-tatooine`, with the same commands (`up`, `deploy`, `ssh`,
`screenshot`, `status`, `down`, `destroy`), the same SSH ports and the same
inventory. Each VM has a NAT card and a card on the internal network
`starwars`. It needs `VBoxManage`, `qemu-img` (`qemu-utils`), `genisoimage`
and `curl`; its checks run with `LAB=lab/vboxlab.sh lab/check.sh`.

What differs from `lab.sh`:

- the VMs' files are in `$LAB_DIR/vbox/<vm>/`, the consoles in
  `$LAB_DIR/vbox/<vm>/serial.log`;
- Tatooine opens in a VirtualBox window, headless without a graphical
  session; there is no VNC, no `LAB_SERVER_SCREEN`, and no `debian` password
  for the screens;
- the ports for your browser (below) are forwarded when the VMs are created:
  lower `ip_unprivileged_port_start` before the first `up`, or `destroy` and
  `up` again;
- it uses the same ports and the same `$LAB_DIR` as `lab.sh`: run one lab at
  a time.

## Using the services from your own browser

Tatooine is the intended client. To use the portal and the console from your
computer's browser as well, the domain controller must answer on ports 80
and 443 of your computer, which an ordinary user cannot open:

```sh
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80   # until the next reboot
lab/lab.sh down      # wait until lab/lab.sh status shows them stopped
lab/lab.sh up
```

With that, `lab.sh up` forwards 80, 443, 88 and 749 of `127.0.0.1` to Coruscant;
without it, `up` prints `ports 80/443/88 not forwarded`. Then, in your
`/etc/hosts`, one name per line (see
[why](deployment.md#reaching-the-services-from-another-computer)):

```
127.0.0.1 coruscant.star.wars
127.0.0.1 auth.star.wars
127.0.0.1 manager.star.wars
127.0.0.1 directory.star.wars
```

and trust the demo CA in your browser:

```sh
lab/lab.sh ssh coruscant cat /etc/star-wars/pki/ca.crt > star-wars-ca.crt
```

In Firefox: Settings → Privacy & Security → Certificates → View
Certificates → Authorities → Import, and tick "Trust this CA to identify
websites". Then open `https://directory.star.wars` and sign in as `yoda`.
See [deployment](deployment.md#reaching-the-services-from-another-computer)
for `kinit` from your computer.

Remove those lines from `/etc/hosts` when you are done.

Rudder's web interface is not forwarded: open it from Tatooine, at
`https://kamino.star.wars/rudder/` (Rudder's own certificate: accept the
warning), as `admin`, with the password in `secrets/star.wars/rudder-admin`.

## Looking inside the VMs

Log in with `lab/lab.sh ssh coruscant` (or `kamino`, `tatooine`), as `debian`,
who has sudo without password; root has no password, as on any cloud image.

Coruscant and Kamino have no screen: their consoles go to
`$LAB_DIR/<vm>/serial.log`.
To see it in a window as well, start it with `LAB_SERVER_SCREEN=1`:

```sh
lab/lab.sh down      # if it runs; wait until lab/lab.sh status shows it stopped
LAB_SERVER_SCREEN=1 lab/lab.sh up
```

and log in there as `debian`, password `debian` (then `sudo -i`). Without a
graphical session, or with `LAB_DISPLAY=vnc`, that screen is on VNC at
`127.0.0.1:5900`. A lab created before this password existed lacks it:
`lab/lab.sh ssh coruscant 'echo debian:debian | sudo chpasswd'`.

The logs worth reading:

```sh
sudo journalctl -f                                    # everything
sudo journalctl -u slapd -u krb5-kdc -u krb5-admin-server
sudo journalctl -u sw-join -u sw-computers -u sw-posix-accounts
sudo docker logs -f lemonldap                         # the SSO
sudo docker logs -f twake-directory-manager           # the console
```

On Kamino, Rudder's web application: `sudo journalctl -u rudder-jetty`, and
`/var/log/rudder/webapp/webapp.log` for the policy generations.

On Tatooine, the logins go through `sssd` and `lightdm`:
`sudo journalctl -u sssd -u lightdm`. `sudo rudder agent info` tells whether
the node is accepted and which policies it has, `sudo rudder agent run`
applies them at once.

## Commands

| Command                                                | Does                                       |
| ------------------------------------------------------ | ------------------------------------------ |
| `lab/lab.sh up`                                        | Creates the VMs if needed and starts them  |
| `lab/lab.sh deploy [ansible args]`                     | Runs the playbook with `lab/inventory.yml` |
| `lab/lab.sh ssh coruscant\|kamino\|tatooine [command]` | SSH as `debian` (sudo without password)    |
| `lab/lab.sh screenshot tatooine shot.png`              | Saves Tatooine's screen                    |
| `lab/check.sh`                                         | Runs the end-to-end checks (see below)     |
| `lab/lab.sh status`                                    | Tells which VMs run                        |
| `lab/lab.sh down`                                      | Shuts the VMs down; `up` starts them again |
| `lab/lab.sh destroy`                                   | Deletes the VMs; the cloud image stays     |

Everything lives in `~/.cache/krb-demo-lab` (or `$LAB_DIR`): the cloud
image, the lab's SSH key, the VM disks and logs.

## Checking the lab

`lab/check.sh` replays, through SSH to the VMs, what a user and an
administrator do, and prints one line per check:

- the services run, and Tatooine's sssd is online;
- yoda and dvador sign in to the console through the SSO, with the rights
  of their organizations, and a wrong password is refused;
- Tatooine knows the accounts, its key is valid, `kinit` works, and hsolo logs
  in on Tatooine with a ticket;
- Tatooine is accepted by Rudder, its agent runs on its own, and it has the
  Firefox policies Rudder hands out;
- a computer goes through its life: created, its principal appears, its
  one-time password gets its keytab once, then it is deleted with its
  principal; a computer may not take the domain controller's name.

It assumes the demo passwords (password = login), leaves the directory as
it found it, and exits with the number of failures.

## Troubleshooting

- **`qemu-img: command not found`**: install `qemu-utils`.
- **`coruscant did not start`** (or `kamino`, `tatooine`), followed by qemu's
  error: most often a port already taken, by another program or a lab started
  from another `LAB_DIR`. `ss -tulpn | grep -E ':(2222|2223|2224|5900|5901) '`
  tells which.
- **`LAB_DIR is too long`**: qemu's monitor sockets live in `$LAB_DIR`, and a
  Unix socket path stops at 107 bytes. Use a shorter directory.
- **`coruscant does not answer on SSH`** (or another VM): look at
  `$LAB_DIR/<vm>/serial.log`, the VM's console, and `$LAB_DIR/<vm>/qemu.log`.
- **The console does not answer from your browser**: the ports are not
  forwarded; see [using the services from your own browser](#using-the-services-from-your-own-browser).
  The lab still works from Tatooine.
- **Typing gives the wrong letters on Tatooine**: the desktop's layout comes from
  your `/etc/default/keyboard` at `deploy` time. Run `deploy` again after
  changing it, or give it: `lab/lab.sh deploy -e "sw_keyboard_layout=fr sw_keyboard_variant=latin9"`.
