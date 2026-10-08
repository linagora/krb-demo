# Joining a PC to the domain

A workstation of the domain is a Debian 13 machine where:

- every account of the directory exists (`getent passwd hsolo`), with no
  local account to create;
- users log in with their directory login and password, and get a Kerberos
  ticket at login;
- Firefox signs them in to the SSO with that ticket, without a password;
- accounts the console disables can no longer log in;
- Rudder keeps its configuration: Firefox's policies, the desktop.

## With the playbook

Add the machine to the `workstations` group of the inventory (see
[deployment](deployment.md#inventory)) and run:

```sh
ansible-playbook site.yml --limit tatooine
```

The inventory name is the host name: `tatooine` becomes `tatooine.star.wars`.
With `sw_workstation_desktop: false`, the machine gets everything but the
desktop; Rudder's rule still applies to it, and installs the screen saver and
drops the desktop's files.

The play needs the domain controller and the Rudder server in the same
inventory: it reads the demo CA on the domain controller, declares the
computer in the directory and sets its one-time join password; then it has
the machine's node accepted through the Rudder server's API.

## What joining does

### 1. Find the domain controller

`/etc/hosts` gets the workstations of the inventory (so that SSH with a
ticket finds them by name), the names of the domain controller, **one per
line**, and the Rudder server:

```
10.10.0.21 tatooine.star.wars tatooine
10.10.0.1 coruscant.star.wars coruscant
10.10.0.1 auth.star.wars
10.10.0.1 manager.star.wars
10.10.0.1 directory.star.wars
10.10.0.2 kamino.star.wars kamino
```

The first name of a line is the canonical name of the address, and Firefox
asks for a Kerberos ticket for the canonical name. On one line, `auth` would
be known as `coruscant`, Firefox would ask for `HTTP/coruscant.star.wars`, a principal that
does not exist, and fall back to the login form.

### 2. Trust the demo CA

The CA of the domain controller goes into the system's trust store, as
`/usr/local/share/ca-certificates/star-wars-demo-ca.crt`, for sssd's StartTLS
and for the command line; Firefox's policies import it from that path.

### 3. Join the realm

`/etc/krb5.conf` names the realm and its KDC. The machine is then joined
the way [computers](computers.md) are joined by hand:

1. the playbook declares the computer in the directory (`cn=tatooine,ou=computers`,
   in the organization `sw_workstation_organization`, the top one by
   default), where the console shows it;
2. it sets a one-time join password on it;
3. on the machine, `star-wars-join` trades that password for the keytab of
   `host/tatooine.star.wars@STAR.WARS`, installed as `/etc/krb5.keytab`.

The machine's key lets sssd check that the ticket it gets at login comes
from the real KDC, and lets other machines of the domain log in to it over
SSH with their ticket. It also ties the machine to its computer in the
console: disabling the computer stops every login on the machine.

A run of the playbook joins the machine again only when its key no longer
works (`kinit -k` fails): a reinstalled machine, a principal recreated. A
computer disabled in the console is left alone: re-enabling it is an
administrator's call.

### 4. Identities and logins: sssd

`/etc/sssd/sssd.conf`, in short:

| Setting                    | Effect                                                                                                                       |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `id_provider = ldap`       | Accounts come from `ou=users`, their Unix group from `ou=unix`, read with the `cn=workstation` service account over StartTLS |
| `auth_provider = krb5`     | The password is checked by the KDC, which hands out a ticket                                                                 |
| `krb5_validate = true`     | The ticket is checked with the machine's key                                                                                 |
| `access_provider = ldap`   | Only accounts whose state is **Active** may log in                                                                           |
| `chpass_provider = none`   | Passwords change on the SSO portal, not on the machine                                                                       |
| `cache_credentials = true` | Users who logged in once can log in while the domain controller is unreachable                                               |

The accounts' Unix attributes (`uidNumber`, home, shell) come from the
domain controller, which hands them out to every account the console
creates (see [administration](administration.md#creating-an-account)).
Home directories are created at first login (`pam_mkhomedir`).

### 5. SSH

`sshd` accepts Kerberos tickets (`GSSAPIAuthentication`) and passwords.
From another machine of the domain, `ssh tatooine.star.wars` logs in with the
ticket, no password asked.

### 6. The desktop

With `sw_workstation_desktop` (the default):

- the standard Debian kernel replaces the cloud one, which has no display
  drivers (the machine reboots once);
- XFCE, with LightDM asking for a login: domain accounts are not listed;
- the keyboard layout `sw_keyboard_layout` / `sw_keyboard_variant`, for the
  login screen as well;
- Firefox, whose policies come from Rudder (next step).

### 7. Rudder

The `rudder_agent` role installs the Rudder agent, points it at the server,
has the node accepted and applies its policies before the play ends (see
[Rudder](rudder.md#the-agent)). The agent then runs every five minutes, and
puts back what was changed by hand:

- Firefox's policies, `/etc/firefox/policies/policies.json`: Kerberos SSO
  allowed on `.star.wars`, the demo CA, the portal as home page, a bookmarks
  bar with the portal, the console and the manager, and no offer to save
  passwords;
- a locked wallpaper, blue or red (`sw_rudder_wallpaper`);
- a locked screen saver, `xfce4-screensaver`, which blanks the screen after
  five minutes and locks it (`light-locker` is removed);
- `star-wars-refresh-desktop.path`, which restarts the wallpaper and the screen
  saver of the open sessions when their files change.

## By hand, on any Debian

For a machine outside the playbook, the same steps:

```sh
# 1-2: /etc/hosts as above, and the CA
sudo cp star-wars-ca.crt /usr/local/share/ca-certificates/star-wars-demo-ca.crt
sudo update-ca-certificates

# 3-4: the packages, then /etc/krb5.conf and /etc/sssd/sssd.conf (mode 640)
#      from the templates in roles/kerberos/templates/ and
#      roles/workstation/templates/
sudo apt install ca-certificates curl krb5-user ldap-utils sssd sssd-ldap sssd-krb5 sssd-tools libnss-sss libpam-sss
sudo pam-auth-update --enable mkhomedir

# 3: create the computer in the console, reset its password, and join with
#    it; the machine's host name must be pc9 (star-wars-join is rendered from
#    roles/workstation/templates/star-wars-join.j2)
sudo star-wars-join pc9
```

Then the Rudder agent, for Firefox's policies and the desktop: install
`rudder-agent` from Rudder's repository, `sudo rudder agent policy-server
kamino.star.wars`, and accept the node in Rudder's web interface (Node
management → **Pending nodes**).

The workstation service account's password is in
`secrets/star.wars/ldap-workstation` on the Ansible controller.

## Checking a workstation

```sh
getent passwd hsolo                     # the account, from the directory
id lskywalker                           # uid, and the starwars group
sudo sssctl domain-status star.wars     # "Online status: Online"
sudo klist -k /etc/krb5.keytab          # host/tatooine.star.wars@STAR.WARS
sudo kinit -k -c MEMORY:x host/tatooine.star.wars   # the key works
sudo rudder agent info                  # "Configuration id: …": accepted, with its policies
grep auth.star.wars /etc/firefox/policies/policies.json   # Firefox's policies
```

## Troubleshooting

| Symptom                                                                                   | Cause                                                                                                                                                                                                 |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `getent passwd hsolo` answers nothing, sssd says _Offline_                                | sssd cannot reach slapd or its StartTLS: check `coruscant.star.wars` resolves, port 389 is open, the CA is trusted. Logs: `/var/log/sssd/sssd_star.wars.log`                                          |
| The password is right, the login is refused, and `krb5_child.log` says _PAC check failed_ | The KDC puts a PAC in tickets, which sssd cannot check without AD or IPA. The playbook turns PACs off on the KDC (`disable_pac`)                                                                      |
| The login is refused for a new account                                                    | It has no Kerberos key yet: it must sign in once on the SSO portal (see [administration](administration.md#creating-an-account))                                                                      |
| `Access denied` in the journal                                                            | The account is not Active                                                                                                                                                                             |
| Every new login is refused, with _System error_ in the journal                            | The computer is disabled in the console: its principal gets no tickets, so sssd cannot check any login                                                                                                |
| `star-wars-join` answers _unknown computer or wrong password_                             | The computer does not exist in the console, or its password was used already, mistyped, or locked after five failures (ten minutes)                                                                   |
| `star-wars-join` answers _this computer is disabled_                                      | Enable it in the console, and reset its password again: the refused attempt spent it                                                                                                                  |
| `star-wars-join` answers _this host is not managed by the console_                        | Its host principal was created by other means: the console cannot hand it over                                                                                                                        |
| Firefox shows the login form instead of signing in                                        | No ticket (`klist`); no policies (`about:policies` is empty: `sudo rudder agent update && sudo rudder agent run`); or the name issue of step 1: the KDC's log tells which principal Firefox asked for |
| Clock skew errors                                                                         | Kerberos refuses clocks more than five minutes apart: check `timedatectl` on both machines                                                                                                            |
