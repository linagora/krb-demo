# Network setup on VirtualBox

For machines you installed yourself in VirtualBox (for the automatic version,
see `lab/vboxlab.sh` in the [lab](lab.md#on-virtualbox)). Each VM gets two
cards:

| Card | Mode | For |
|---|---|---|
| 1 | NAT | Internet (packages), and SSH from the host through port forwarding |
| 2 | Internal network `starwars` | The domain's private network, `10.10.0.0/24` |

| VM | Private address | SSH from the host |
|---|---|---|
| `coruscant` | `10.10.0.1` | `127.0.0.1:2222` |
| `tatooine` | `10.10.0.21` | `127.0.0.1:2223` |
| `kamino` | `10.10.0.2` | `127.0.0.1:2224` |

An internal network has no DHCP and the host is not on it: addresses are
static, and a browser on the host does not reach the services (see the end).

## 1. Cards, on the host

List VMS :

```sh
VBoxManage list vms
```


With the VMs powered off (replace the names with yours):

```sh
for vm in krb-demo-coruscant krb-demo-kamino krb-demo-tatooine; do
  VBoxManage modifyvm "$vm" --nic2 intnet --intnet2 starwars --nictype2 virtio
done

# SSH from the host, on the NAT card (optional)
VBoxManage modifyvm krb-demo-coruscant     --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
VBoxManage modifyvm krb-demo-tatooine    --natpf1 "ssh,tcp,127.0.0.1,2223,,22"
VBoxManage modifyvm krb-demo-kamino --natpf1 "ssh,tcp,127.0.0.1,2224,,22"
```

Check:

```sh
VBoxManage showvminfo krb-demo-coruscant --machinereadable | grep -E '^(nic|intnet|Forwarding)'
```

The same can be done in the graphical interface: Settings → Network →
Adapter 2 → Enable, "Internal Network", name `starwars`.

## 2. Static address, in each VM

Find the second card's name (the one without an address):

```sh
ip -br link        # e.g. enp0s8
```

On a Debian installed from the netinstall (ifupdown), in
`/etc/network/interfaces.d/lan`:

```
auto enp0s8
iface enp0s8 inet static
    address 10.10.0.1/24
```

```sh
sudo ifup enp0s8
```

On a cloud image (systemd-networkd), in `/etc/systemd/network/20-lan.network`:

```ini
[Match]
Name=enp0s8

[Network]
Address=10.10.0.1/24
```

```sh
sudo systemctl restart systemd-networkd
```

Use `10.10.0.1`, `10.10.0.2` or `10.10.0.21` according to the VM. No gateway,
no DNS: the NAT card keeps both.

## 3. Check

From each VM:

```sh
ping -c1 10.10.0.1; ping -c1 10.10.0.2; ping -c1 10.10.0.21
```

and the NAT card still reaches the Internet (`apt update`).

## 4. The controller

Ansible runs from a fourth machine, the controller (here, the VM holding
this repository). Give it a card on the same internal network, and an
address that is not a VM's:

```sh
VBoxManage modifyvm <controller> --nic2 intnet --intnet2 starwars --nictype2 virtio
```

then, inside it, as in step 2, with `10.10.0.100/24`. It reaches the three
VMs directly: the SSH redirections of step 1 are not needed (they stay
useful from the host).

On the controller:

```sh
sudo apt install ansible
ansible-galaxy collection install -r requirements.yml
ssh-copy-id debian@10.10.0.1; ssh-copy-id debian@10.10.0.2; ssh-copy-id debian@10.10.0.21
```

(`debian` being a user with sudo on each VM.)

## 5. Inventory

```sh
cp inventory.example.yml inventory.yml
```

The addresses must be set by hand: the default ones come from the machine's
*default route*, which is the NAT card (`10.0.2.15`, the same on every VM).

```yaml
all:
  vars:
    ansible_user: debian
    ansible_become: true
    sw_dc_address: 10.10.0.1
  children:
    domain_controller:
      hosts:
        coruscant:
          ansible_host: 10.10.0.1
    rudder_server:
      hosts:
        kamino:
          ansible_host: 10.10.0.2
          sw_rudder_address: 10.10.0.2
    workstations:
      hosts:
        tatooine:
          ansible_host: 10.10.0.21
          sw_workstation_address: 10.10.0.21
          sw_keyboard_layout: fr
```

```sh
ansible-playbook site.yml
```

## From a browser on the host (optional)

The internal network is closed to the host. Either forward the ports of `coruscant`
(80, 443, 88; the host needs `sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80`
for the first ones) and follow
[the lab](lab.md#using-the-services-from-your-own-browser), or replace the
internal network by a **host-only network** (`--nic2 hostonly
--hostonlyadapter2 vboxnet0`), where the host gets an address too, and use
that network's addresses instead of `10.10.0.x`.
