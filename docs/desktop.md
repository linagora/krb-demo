# Using a workstation of the domain

A tour of a user's day on `tatooine`, as Luke Skywalker.

## Logging in

The login screen asks for a login and a password: type `lskywalker` and
`lskywalker`. There is no local account: the login is checked by the
domain's KDC, and Luke's account comes from the directory.

At the first login, the home directory `/home/lskywalker` is created.

## The Kerberos ticket

The login hands out a ticket, valid for ten hours. In a terminal:

```console
$ klist
Ticket cache: FILE:/tmp/krb5cc_10003_tBPtjZ
Default principal: lskywalker@STAR.WARS

Valid starting       Expires              Service principal
06/10/2026 13:06:31  06/10/2026 23:06:31  krbtgt/STAR.WARS@STAR.WARS
```

Should it expire during a long session, `kinit` asks for the password and
fetches a new one.

## The web, without passwords

Open Firefox. Its home page is the SSO portal, `https://auth.star.wars`:
it greets Luke at once, "Connected as lskywalker", with the applications he
may use. Behind the scenes, Firefox handed the portal a ticket for
`HTTP/auth.star.wars`.

The bookmarks bar leads to:

- **SSO portal**: the applications, the login history, the logout;
- **Directory**: Twake Directory Manager. Luke administers nothing, so the
  console tells him so; `lorgana` or `yoda` would see their organizations
  (see [who administers what](administration.md#who-may-do-what));
- **SSO manager**: the LemonLDAP::NG configuration, for the Jedi Council
  only.

Logging out of the portal ends the web session, not the desktop one: the
next visit signs in again with the ticket.

## Other machines of the domain

With the ticket, SSH needs no password either:

```sh
ssh pc2.star.wars
```

## Changing one's password

Passwords are changed on the SSO portal, in its **Password** tab, not on
the machine (`passwd` refuses).

The workstations check passwords against Kerberos, whose key follows the
directory at each **sign-in with a password on the portal**, and a sign-in by
Kerberos SSO carries no password. So after a change, on a workstation:

1. drop the ticket, so that the portal shows its form: `kdestroy` in a
   terminal;
2. in Firefox, log out of the portal and sign in again, with the new
   password;
3. get a ticket back: `kinit`, with the new password.

Until step 2, the workstations still take the old password, for the login
screen as for `kinit`.

The same goes after an administrator resets a password: see
[administration](administration.md#resetting-a-password).

## A new account

An account just created in the console has no Kerberos key until its first
sign-in with a password on the portal. Before logging in on a workstation
for the first time, sign in once on `https://auth.star.wars`, from any
browser, with the password the administrator gave.

## When something goes wrong

| What you see                                                              | What to do                                                                                                                                                             |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Your password is incorrect" at the login screen, with the right password | A recent password change: sign in on the portal with the new password from any browser without a ticket, then log in again. A new account: sign in on the portal first |
| The login is refused at once                                              | The account is disabled: see an administrator                                                                                                                          |
| Firefox shows the login form                                              | `klist` in a terminal: no ticket, run `kinit`, then reload the page                                                                                                    |
| `kinit: Clock skew too great`                                             | The machine's clock is wrong                                                                                                                                           |
