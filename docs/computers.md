# Computers

The workstations of the domain are entries of the directory, managed in Twake
Directory Manager like the accounts: **Computers** in the sidebar. A computer
in the console is what the KDC knows of the machine:

| In the console        | On the domain                                                                                               |
| --------------------- | ----------------------------------------------------------------------------------------------------------- |
| A computer is created | Its principal `host/<name>.star.wars` exists, with a random key                                             |
| Its password is reset | The console shows a **one-time join password**, which `star-wars-join` on the machine trades for its keytab |
| It is disabled        | Its principal gets no new tickets: **new logins on the machine are refused**                                |
| It is enabled again   | Logins work again                                                                                           |
| It is deleted         | Its principal is deleted                                                                                    |

## Who manages which computers

As for accounts, through the organization tree: a computer belongs to an
organization, and whoever administers that organization manages it. `dvador`
creates and disables the Galactic Empire's computers, not the Rebel
Alliance's; `yoda` manages them all (see
[who may do what](administration.md#who-may-do-what)).

## Joining a new machine

1. **In the console**, create the computer: its host name (`pc2`: lower case,
   digits and hyphens, the machine's short name) and its organization. A
   description, a location, a serial number and an owner are optional.
2. On its card, **reset its password**. The console shows a one-time join
   password, once: copy it.
3. **On the machine**, a Debian 13 set up as a [workstation](workstation.md)
   (sssd, Kerberos client), as root:

   ```console
   # star-wars-join
   One-time password of pc2: ••••••••••••••••
   pc2.star.wars joined the domain
   ```

The password works once: the join replaces it with a random one nobody
knows, even when it then refuses (a disabled computer). To join the machine
again, after a reinstallation say, reset the password again.

The playbook does the same for the workstations of its inventory: it
creates the computer, sets a one-time password and runs `star-wars-join`
(see [joining a PC](workstation.md#3-join-the-realm)).

## Behind the console

### The reconciler

`sw-computers`, a timer on the domain controller, runs every 30 seconds and
brings the KDC in step with `ou=computers`:

- a computer without a principal gets one, created with a random key and
  the kadmin policy `workstation`;
- an active computer's principal may get tickets (`+allow_tix`), a disabled
  one's may not (`-allow_tix`);
- a principal `host/*.star.wars` with the policy `workstation` and no
  computer left is deleted.

The policy is the reconciler's mark: it never touches a principal it did not
create. Its actions are in `journalctl -u sw-computers`.

### The join service

`sw-join` answers `POST https://coruscant.star.wars/join`, with the form fields
`host` and `password`:

1. it binds to the directory as the computer, `cn=<host>,ou=computers`,
   with the password: that is the check;
2. it replaces the password with a random one nobody keeps: it worked
   once, even if what follows fails. Joins run one at a time, and the
   policy requires the current password for a change: two requests racing
   with the same password cannot both succeed;
3. it refuses a disabled computer, and a principal it did not create;
4. it gives the principal a new random key and answers with its keytab.

Guessing is held back three ways. The computers' password policy locks a
computer after five wrong passwords, for ten minutes. nginx lets through six
requests a minute per address, after a burst of five. And an unknown computer gets the same answer
as a wrong password.

The service runs as the `sw-join` user, not root. It reaches kadmind as
`join/service@STAR.WARS`, which `kadm5.acl` allows to inquire, add and
change `host/*` principals only. Its logs: `journalctl -u sw-join`.

### In the directory

A computer is a `device` (its `cn` is the host name) with two auxiliary
classes:

- `twakeWhitePages`, for its organization;
- `demoWorkstation`, a class of the demo for its state (`twakeAccountStatus`)
  and its join password.

The console learns the entity from `computers.json`, a schema added to the
image's own (`DM_LDAP_FLAT_SCHEMA`). A computer bound with its password reads
its own entry and nothing else.

The join password is only ever set by a reset: the schema marks it
read-only, so the console's forms leave it out. Offered next to the host
name, it made the creation form look like a login form, and browsers filled
in the administrator's own login and password.

## Limits

- The keytab travels over HTTPS, protected by the demo CA, and the one-time
  password is all it takes to get it: pass the password over a safe channel.
- Disabling a computer refuses new logins. Tickets already issued for it stay
  valid until they expire, ten hours at most: an open session, or an SSH
  login with such a ticket, goes on. While the machine cannot reach the
  domain controller, it decides from what it has cached.
- The domain controller's names (`coruscant`, `auth`, `manager`, `directory`) cannot
  be computers. A computer named after a host principal the console did not
  create is left alone by the reconciler, and refused by the join service:
  managing a computer gives no hold on a machine joined by other means.
- Deleting a computer does not touch the machine: its keytab simply stops
  working, and its Rudder node stays accepted until it is removed in Rudder.
