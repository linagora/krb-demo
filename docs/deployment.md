# Deployment

This page installs the demo on machines of your own. To try it on your
computer without any, use the [lab](lab.md).

## Requirements

On the controller (the machine running Ansible):

- ansible-core 2.16 or later;
- the collections: `ansible-galaxy collection install -r requirements.yml`;
- `python3-passlib` and `python3-bcrypt`, for the password of Rudder's
  administrator, hashed on the controller.

The machines are fresh **Debian 13** installs (12 works too for the Rudder
server), reachable over SSH with a sudo account:

| Machine           | Size                         | Network                                                               |
| ----------------- | ---------------------------- | --------------------------------------------------------------------- |
| Domain controller | 2 CPUs, 4 GB RAM, 10 GB disk | Internet access (Debian packages and two container images)            |
| Rudder server     | 2 CPUs, 3 GB RAM, 10 GB disk | Internet access (Rudder's packages, `repository.rudder.io`)           |
| Workstations      | 2 CPUs, 3 GB RAM, 10 GB disk | Reach the domain controller on 88, 389 and 443, and the Rudder server |

Every machine must be able to reach the domain controller at one address,
`sw_dc_address`. It defaults to the domain controller's default IPv4 address
as Ansible sees it; set it in the inventory when the machines talk over
another network.

## Inventory

```sh
cp inventory.example.yml inventory.yml
```

```yaml
all:
  children:
    domain_controller: # exactly one
      hosts:
        coruscant:
          ansible_host: 192.0.2.10
          ansible_user: debian
          ansible_become: true
    rudder_server: # exactly one
      hosts:
        kamino:
          ansible_host: 192.0.2.11
          ansible_user: debian
          ansible_become: true
          sw_rudder_allowed_networks: ["192.0.2.0/24"]
    workstations: # zero or more
      hosts:
        tatooine:
          ansible_host: 192.0.2.21
          ansible_user: debian
          ansible_become: true
          sw_workstation_desktop: true
          sw_keyboard_layout: fr
```

A workstation's inventory name becomes its host name: `tatooine` is
`tatooine.star.wars` in the realm.

Then:

```sh
ansible-playbook site.yml
```

The first run takes a few minutes for the domain controller, and a few more
for each desktop workstation, which reboots once onto the standard kernel
(cloud images ship one without display drivers).

Running the playbook again changes nothing. To add a workstation, add it to
the inventory and run the playbook again; `--limit tatooine` skips the
others, but the Rudder server must still answer over SSH: the workstation's
node is accepted from there.

Workstations reach each other by name through their `/etc/hosts`, at their
default IPv4 address; set `sw_workstation_address` on a workstation when the
others reach it at another one.

## What lands where

### Domain controller

| What                        | Where                                                                                      |
| --------------------------- | ------------------------------------------------------------------------------------------ |
| OpenLDAP                    | Debian package, `ldap://coruscant.star.wars` (StartTLS), base `dc=star,dc=wars`            |
| MIT KDC and kadmind         | Debian packages, realm `STAR.WARS`, ports 88 and 749                                       |
| LemonLDAP::NG               | container `lemonldap`, behind nginx: `https://auth.star.wars`, `https://manager.star.wars` |
| Twake Directory Manager     | container `twake-directory-manager`, behind nginx: `https://directory.star.wars`           |
| Unix identities             | timer `sw-posix-accounts`, every 30 seconds                                                |
| Computers ↔ KDC             | timer `sw-computers`, every 30 seconds                                                     |
| Join service                | `sw-join`, behind nginx: `https://coruscant.star.wars/join`                                |
| Demo CA and certificate     | `/etc/star-wars/pki/`                                                                      |
| LemonLDAP::NG configuration | `/etc/star-wars/llng/over/`, one file per key                                              |
| Keytabs                     | `/etc/star-wars/krb/`                                                                      |

### Rudder server

`rudder-server` from Rudder's repository (`sw_rudder_version`), its web
interface on `https://kamino.star.wars/rudder/` (the server's inventory name),
the files it hands out in
`/var/rudder/configuration-repository/shared-files/star-wars/`, and the API
account `ansible`. See [Rudder](rudder.md).

### Workstations

sssd, the Kerberos client, the host keytab in `/etc/krb5.keytab`, the Rudder
agent, and with the desktop: XFCE, LightDM and Firefox. Firefox's policies
(Kerberos SSO, the demo CA), the locked wallpaper and screen saver come from
Rudder. See [joining a PC](workstation.md).

## Variables

The useful ones; the others are in `group_vars/all.yml` and the roles'
`defaults/`.

| Variable                                    | Default               | Meaning                                                                                                                               |
| ------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `sw_domain`                                 | `star.wars`           | DNS domain; the realm is its upper case, the LDAP base follows it                                                                     |
| `sw_dc_address`                             | the DC's default IPv4 | Address every machine reaches the domain controller at                                                                                |
| `sw_demo_password`                          | empty                 | One password for every demo user; empty, each password is the login                                                                   |
| `sw_workstation_desktop`                    | `true`                | XFCE, LightDM and Firefox on workstations; `false` for command line only                                                              |
| `sw_workstation_organization`               | empty                 | Organization a workstation's computer belongs to in the console, as a path (`Galactic Empire / Imperial Navy`); empty for the top one |
| `sw_keyboard_layout`, `sw_keyboard_variant` | `us`, empty           | Keyboard of the workstations' desktop                                                                                                 |
| `sw_llng_extra_conf`                        | `{}`                  | LemonLDAP::NG keys added to, or replacing, the playbook's                                                                             |
| `sw_llng_image`, `sw_tdm_image`             | pinned                | Container images; the LemonLDAP::NG one is pinned by digest to the tested image                                                       |
| `sw_workstation_address`                    | its default IPv4      | Address the other workstations reach a workstation at                                                                                 |
| `sw_rudder_allowed_networks`                | `["10.10.0.0/24"]`    | Networks the Rudder server accepts agents from: the lab's by default, set it to the workstations' network                             |
| `sw_rudder_address`                         | `ansible_host`        | Address the workstations reach the Rudder server at; set it on the server in the inventory when it differs                            |
| `sw_rudder_version`                         | `9.1`                 | Series of Rudder's APT repository, for the server and the agents                                                                      |
| `sw_rudder_wallpaper`                       | `blue`                | The workstations' wallpaper: `blue` (the Rebels) or `red` (the Empire)                                                                |
| `sw_rudder_debug`                           | `false`               | `true` shows the output the Rudder roles hide, token included                                                                         |

The demo data (users, organizations, groups, positions) is in
`roles/demo_data/defaults/main.yml`.

## Secrets

Generated on the first run, kept on the controller in `secrets/star.wars/`
(ignored by git):

| File                                                           | Secret                                                            |
| -------------------------------------------------------------- | ----------------------------------------------------------------- |
| `ldap-admin`                                                   | `cn=admin,dc=star,dc=wars`                                        |
| `ldap-directory-manager`, `ldap-lemonldap`, `ldap-workstation` | The service accounts of the console, the SSO and the workstations |
| `krb-master`                                                   | The KDC's master key                                              |
| `oidc-directory-manager`                                       | The console's OpenID Connect client secret                        |
| `rudder-admin`                                                 | The password of Rudder's web interface administrator, `admin`     |
| `rudder-api-token`                                             | The token of Rudder's API account, created by the playbook        |

Keep this directory to run the playbook again from elsewhere. Without it, a
run generates new secrets: the service accounts, the OpenID Connect client
and Rudder's administrator and API account take them, but `ldap-admin` and
`krb-master` are only used when the directory and the realm are created, so
the new files would not match the machines. Nothing in the demo needs those
two afterwards; `sudo` on the domain controller reaches both the directory
(`ldapi:///`) and the KDC (`kadmin.local`).

## Reaching the services from another computer

A browser on a computer outside the domain can use the portal and the
console, with the login form instead of Kerberos SSO. It needs two things.

**Names.** The services are reached by name only: nginx and the SSO tell
them apart by name, the SSO cookie belongs to `.star.wars`, and the OpenID
Connect redirections carry full URLs. `.wars` is not a real top-level
domain: add the names to `/etc/hosts`, **one per line**:

```
192.0.2.10 coruscant.star.wars
192.0.2.10 auth.star.wars
192.0.2.10 manager.star.wars
192.0.2.10 directory.star.wars
192.0.2.11 kamino.star.wars
```

(the last one for Rudder's web interface).

One per line matters for Kerberos: the first name of a line is the
canonical one, and a browser asks for a ticket for the canonical name. With
all the names on one line, it asks for `HTTP/coruscant.star.wars` instead of
`HTTP/auth.star.wars`, and Kerberos SSO fails.

Type the `https://` prefix: browsers may take a bare `directory.star.wars`
for a search.

**Trust.** Import the demo CA, `/etc/star-wars/pki/ca.crt` on the domain
controller, into the browser, or accept the warnings.

For `kinit` from that computer, point a `krb5.conf` at the KDC:

```ini
[libdefaults]
    default_realm = STAR.WARS
    dns_lookup_kdc = false
    rdns = false
[realms]
    STAR.WARS = {
        kdc = coruscant.star.wars
        admin_server = coruscant.star.wars
    }
```

```sh
KRB5_CONFIG=./krb5.conf kinit hsolo
```

## Limits

- **Network exposure.** slapd, the KDC and kadmind listen on every interface:
  the containers reach them through the Docker bridge, the workstations over
  the network. LDAP refuses anonymous reads; users are locked out for five
  minutes after ten bad passwords, while the service accounts have a policy
  without lockout, so that nobody can lock the services out.
- **Containers to slapd.** LemonLDAP::NG and the console talk to slapd over
  the Docker bridge without TLS.
- **Images.** The LemonLDAP::NG image is pinned by digest to the tested one
  (LemonLDAP::NG 2.23.2), the console to 0.4.1.
- **LemonLDAP::NG configuration.** The keys the playbook sets are laid over
  the image's configuration through its overlay backend
  (`roles/lemonldap/templates/llng-conf.yml.j2`): they win over what the
  manager saves.
