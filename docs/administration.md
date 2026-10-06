# Administration

Users, organizations and groups are managed in **Twake Directory Manager**,
at `https://directory.star.wars`. This page tells what the demo adds around
it: who may do what, and what follows from each action on the SSO, on
Kerberos and on the workstations. For the screens themselves, see the
console's [administration guide](https://github.com/linagora/twake-directory-manager/tree/main/docs/admin-guide).

## Signing in

Open `https://directory.star.wars`. The console sends you to the SSO portal
and back. From a workstation of the domain, the portal recognises you from
your Kerberos ticket and asks nothing; elsewhere, it shows its login form.

## Who may do what

An account administers the organizations it is named administrator of
(`twakeLocalAdminLink`), and everything below them: their sub-organizations
and the accounts and groups attached to any of them.

```
organization                      yoda        (the whole directory)
├── Jedi Order                    okenobi
├── Rebel Alliance                lorgana
│   └── Rogue Squadron            wantilles   (lorgana too, from above)
├── Galactic Empire               dvador
│   └── Imperial Navy             wtarkin     (dvador too, from above)
└── Outer Rim                     lcalrissian
```

So `dvador` can reset Tarkin's password but not Han Solo's, `lorgana`
manages Luke (Rogue Squadron) but not Boba Fett (Outer Rim), and `hsolo`
signs in to a console that tells him he administers nothing.

The administrators of an organization are chosen on its card in the
console. Those of the top organization, `ou=organization`, can only be set
in LDAP:

```sh
# on the domain controller
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<'EOF'
dn: ou=organization,dc=star,dc=wars
changetype: modify
add: twakeLocalAdminLink
twakeLocalAdminLink: uid=okenobi,ou=users,dc=star,dc=wars
EOF
```

The SSO configuration, in the LemonLDAP::NG manager at
`https://manager.star.wars`, is open to members of the `jedi-council` group
(`yoda` and `okenobi`). Adding someone to that group in the console opens
the manager to them at their next sign-in.

## Accounts

### Creating an account

In the console, create the account in an organization you administer. The
**login is the part of the email address before the `@`**: an account
created with `padme.amidala@star.wars` signs in as `padme.amidala`. The
address must belong to a domain the directory knows (`star.wars`).

Then, behind the console:

1. **Within 30 seconds**, the `sw-posix-accounts` timer of the domain
   controller gives the account its Unix identity: a `uidNumber` from 10001
   up, the `starwars` group, `/home/<login>` and bash. Workstations can see
   the account from then on.
2. **At the account's first sign-in on the SSO portal with its password**,
   LemonLDAP::NG creates its Kerberos principal with that password.

Until step 2, the account has no Kerberos key: it **cannot log in on a
workstation** yet. Hand the password over, and ask the user to sign in once
on `https://auth.star.wars`, from any browser, before using a workstation.

### Resetting a password

Reset the password on the account's card. With **Require a change at next
sign-in** checked, the directory marks the password as reset.

What the user then does:

1. Sign in on the portal with the new password. The portal asks for a
   password of their own, and sets it.
2. **Sign in on the portal once more**, with that password. This login sets
   the Kerberos key. On a workstation of the domain, run `kdestroy` first:
   with a ticket, the portal signs in by Kerberos and sees no password (see
   [the user's side](desktop.md#changing-ones-password)).

Until step 2, workstations still take the **old** password: they check
passwords against Kerberos, whose key only follows the directory at a
password sign-in on the portal. See
[why](#why-kerberos-follows-the-portal).

### Disabling an account

Set the account's state to **Disabled**, **No access** or **To be deleted**.
Only **Active** accounts may:

- sign in on the SSO portal, and hence on the console and any other
  application behind it;
- log in on a workstation (sssd refuses the others).

Kerberos itself knows nothing of the state: `kinit` still works for a
disabled account, but nothing in the domain accepts its tickets. A
workstation that cannot reach the domain controller decides from what it
remembers of its last contact with the directory.

### Deleting an account

Deleting an account removes it from the directory: it no longer signs in
anywhere. Its Kerberos principal stays; nothing accepts its tickets, but you
can remove it as well:

```sh
sudo kadmin.local -q "delprinc -force padme.amidala"
```

New Unix ids are handed out above the highest one in the directory: the
id of a deleted account comes back only if it was the highest.

## Organizations and groups

Organizations are created, edited and deleted in the console; accounts and
groups are attached to one.

Groups (`ou=groups`) are directory groups: mailing lists, teams, and the
`jedi-council` group the SSO reads. They are **not Unix groups** on the
workstations, where every account belongs to `starwars` only.

## Why Kerberos follows the portal

The directory keeps passwords hashed; Kerberos needs a key derived from the
password in clear. The only moment the clear password is seen is a sign-in
on the SSO portal: there, LemonLDAP::NG's `krb-provisioning` plugin sets the
user's Kerberos key to the password it has just checked, creating the
principal if needed.

Hence the rule: **after any password change, one password sign-in on the
portal brings Kerberos up to date.** A sign-in by Kerberos SSO does not, as
it carries no password, and neither does the change itself.

## From the command line

On the domain controller:

| Task | Command |
|---|---|
| Read an account | `sudo ldapsearch -LLL -Q -Y EXTERNAL -H ldapi:/// -b dc=star,dc=wars uid=hsolo` |
| Who administers what | `sudo ldapsearch -LLL -Q -Y EXTERNAL -H ldapi:/// -b ou=organization,dc=star,dc=wars twakeLocalAdminLink` |
| List the principals | `sudo kadmin.local -q listprincs` |
| A principal's details | `sudo kadmin.local -q "getprinc hsolo"` |
| Set a Kerberos password by hand | `sudo kadmin.local -q "cpw hsolo"` |
| Unix ids handed out lately | `journalctl -u sw-posix-accounts` |
| Hand them out now | `sudo /usr/local/sbin/sw-posix-accounts` |
| The SSO's logs | `sudo docker logs lemonldap` |
| The console's logs | `sudo docker logs twake-directory-manager` |

On a workstation, `sudo sss_cache -E` drops what sssd remembers, so that a
change in the directory shows at once.
