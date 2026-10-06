# Joining a PC to the domain

A workstation of the domain is a Debian 13 machine where:

- every account of the directory exists (`getent passwd hsolo`), with no
  local account to create;
- users log in with their directory login and password, and get a Kerberos
  ticket at login;
- Firefox signs them in to the SSO with that ticket, without a password;
- accounts the console disables can no longer log in.

## With the playbook

Add the machine to the `workstations` group of the inventory (see
[deployment](deployment.md#inventory)) and run:

```sh
ansible-playbook site.yml --limit pc1
```

The inventory name is the host name: `pc1` becomes `pc1.star.wars`. With
`sw_workstation_desktop: false`, the machine gets everything but the
desktop.

The play needs the domain controller in the same inventory: it creates the
machine's principal there.

## What joining does

### 1. Find the domain controller

`/etc/hosts` gets the names of the domain controller, **one per line**:

```
10.10.0.1 dc.star.wars dc
10.10.0.1 auth.star.wars
10.10.0.1 manager.star.wars
10.10.0.1 directory.star.wars
```

The first name of a line is the canonical name of the address, and Firefox
asks for a Kerberos ticket for the canonical name. On one line, `auth` would
be known as `dc`, Firefox would ask for `HTTP/dc.star.wars`, a principal that
does not exist, and fall back to the login form.

### 2. Trust the demo CA

The CA of the domain controller goes into the system's trust store
(`/usr/local/share/ca-certificates/`), for sssd's StartTLS and for the
command line.

### 3. Join the realm

`/etc/krb5.conf` names the realm and its KDC. The machine is then joined
the way [computers](computers.md) are joined by hand:

1. the playbook declares the computer in the directory (`cn=pc1,ou=computers`,
   in the organization `sw_workstation_organization`, the top one by
   default), where the console shows it;
2. it sets a one-time join password on it;
3. on the machine, `star-wars-join` trades that password for the keytab of
   `host/pc1.star.wars@STAR.WARS`, installed as `/etc/krb5.keytab`.

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

| Setting | Effect |
|---|---|
| `id_provider = ldap` | Accounts come from `ou=users`, their Unix group from `ou=unix`, read with the `cn=workstation` service account over StartTLS |
| `auth_provider = krb5` | The password is checked by the KDC, which hands out a ticket |
| `krb5_validate = true` | The ticket is checked with the machine's key |
| `access_provider = ldap` | Only accounts whose state is **Active** may log in |
| `chpass_provider = none` | Passwords change on the SSO portal, not on the machine |
| `cache_credentials = true` | Users who logged in once can log in while the domain controller is unreachable |

The accounts' Unix attributes (`uidNumber`, home, shell) come from the
domain controller, which hands them out to every account the console
creates (see [administration](administration.md#creating-an-account)).
Home directories are created at first login (`pam_mkhomedir`).

### 5. SSH

`sshd` accepts Kerberos tickets (`GSSAPIAuthentication`) and passwords.
From another machine of the domain, `ssh pc1.star.wars` logs in with the
ticket, no password asked.

### 6. The desktop

With `sw_workstation_desktop` (the default):

- the standard Debian kernel replaces the cloud one, which has no display
  drivers (the machine reboots once);
- XFCE, with LightDM asking for a login: domain accounts are not listed;
- the keyboard layout `sw_keyboard_layout` / `sw_keyboard_variant`, for the
  login screen as well;
- Firefox, with policies in `/etc/firefox/policies/policies.json`:
  Kerberos SSO allowed on `.star.wars`, the demo CA, the portal as home page,
  a bookmarks bar with the portal, the console and the manager, and no
  offer to save passwords.

## By hand, on any Debian

For a machine outside the playbook, the same steps:

```sh
# 1-2: /etc/hosts as above, and the CA
sudo cp star-wars-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates

# 3-4: the packages, then /etc/krb5.conf and /etc/sssd/sssd.conf (mode 640)
#      from the templates in roles/kerberos/templates/ and
#      roles/workstation/templates/
sudo apt install curl krb5-user sssd sssd-ldap sssd-krb5 libnss-sss libpam-sss
sudo pam-auth-update --enable mkhomedir

# 3: create the computer in the console, reset its password, and join with
#    it (star-wars-join comes from roles/workstation/templates/)
sudo star-wars-join pc9
```

The workstation service account's password is in
`secrets/star.wars/ldap-workstation` on the Ansible controller.

## Checking a workstation

```sh
getent passwd hsolo                     # the account, from the directory
id lskywalker                           # uid, and the starwars group
sudo sssctl domain-status star.wars     # "Online status: Online"
sudo klist -k /etc/krb5.keytab          # host/pc1.star.wars@STAR.WARS
sudo kinit -k -c MEMORY:x host/pc1.star.wars   # the key works
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| `getent passwd hsolo` answers nothing, sssd says *Offline* | sssd cannot reach slapd or its StartTLS: check `dc.star.wars` resolves, port 389 is open, the CA is trusted. Logs: `/var/log/sssd/sssd_star.wars.log` |
| The password is right, the login is refused, and `krb5_child.log` says *PAC check failed* | The KDC puts a PAC in tickets, which sssd cannot check without AD or IPA. The playbook turns PACs off on the KDC (`disable_pac`) |
| The login is refused for a new account | It has no Kerberos key yet: it must sign in once on the SSO portal (see [administration](administration.md#creating-an-account)) |
| `Access denied` in the journal | The account is not Active |
| Every new login is refused, with *System error* in the journal | The computer is disabled in the console: its principal gets no tickets, so sssd cannot check any login |
| `star-wars-join` answers *unknown computer or wrong password* | The computer does not exist in the console, or its password was used already, mistyped, or locked after five failures (ten minutes) |
| `star-wars-join` answers *this computer is disabled* | Enable it in the console, and reset its password again: the refused attempt spent it |
| `star-wars-join` answers *this host is not managed by the console* | Its host principal was created by other means: the console cannot hand it over |
| Firefox shows the login form instead of signing in | No ticket (`klist`), or the name issue of step 1: the KDC's log tells which principal Firefox asked for |
| Clock skew errors | Kerberos refuses clocks more than five minutes apart: check `timedatectl` on both machines |
