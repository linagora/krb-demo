# Rudder: configuration of the workstations

Rudder (community edition) deploys the workstations' configuration:
wallpaper, screen saver, Firefox, and soon menus, permissions and
prohibitions. It is the domain's equivalent of group policies.

**The line between the two tools.** Ansible builds: it installs the machines,
joins them to the domain and puts the Rudder agent on them. From there,
**Rudder configures and keeps the configuration**: what a workstation should
look like is decided in `rudder/` and `roles/rudder_server/vars/`, not in the
`workstation` role. A setting changed by hand on a workstation comes back at
the agent's next run (every five minutes).

**Status: in progress.** Working, checked on a workstation: the server, the
agent, a locked wallpaper that can be switched, a locked screen saver,
Firefox's policies, packages. To do: per group rules, menus, prohibitions.

## The server

`rudder_server` group of the inventory, one machine, a fresh **Debian 13**
(12 works too: both are supported by Rudder 9.1). In the lab it is the
`kamino` VM, 3 GB of RAM.

```sh
ansible-playbook site.yml --limit kamino
```

The role adds Rudder's APT repository (`sw_rudder_version`, 9.1), installs
`rudder-server` and sets the web interface's administrator from
`sw_rudder_admin` and the password generated in
`secrets/star.wars/rudder-admin`. The interface is on
`https://rudder.star.wars/rudder/`, with Rudder's own certificate.

The password is stored as a bcrypt hash (Rudder 9 refuses the older ones), which
the controller computes: it needs `python3-passlib` and `python3-bcrypt`
(`sudo apt install python3-passlib python3-bcrypt`).

## The agent

The `rudder_agent` role runs after `workstation`, when the inventory has a
`rudder_server`: it adds the same APT repository, installs `rudder-agent`,
points it at the server, sends its inventory and starts the agent's scheduler
(`rudder-cf-execd`, which the package leaves stopped until a reboot).

It then has the node accepted through the API, waiting for the server to
process its inventory, and fetches and applies its policies at once: the
workstation is configured when the playbook ends, not five minutes later. A
workstation reinstalled comes back under a new node id: the server refuses two
nodes of the same name, so the role removes the former one first.
Without an API token (the server deployed from another controller, without
these secrets), the role says so: run the playbook on the Rudder server, which
creates one, or accept the node in the web interface: Node management →
**Pending nodes**.

## API token

What goes through the REST API (the allowed networks, the directives, the
rules, accepting the nodes) needs a token. The REST API cannot create the first
one: the role logs in to the web interface as the administrator and creates,
through the interface's own API (`/rudder/secure/api/apiaccounts`), the API
account `sw_rudder_api_account` (`ansible`), with the administrator's rights.

Its token is shown once only: the role keeps it in
`secrets/star.wars/rudder-api-token`. When the file is missing, or when the
server no longer knows the token (a server rebuilt), the role deletes the
account and creates it again, with a new token.

## What is deployed, and how

`rudder/` holds the files, `roles/rudder_server/vars/` the catalogue:

| Where                                        | What                                                                                                                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `rudder/shared-files/`                       | Files handed out as they are (wallpapers, xfconf files)                                                                               |
| `rudder/shared-files/star-wars/workstation/` | The workstation's own plumbing: the command that restarts the desktop's wallpaper and screen saver, and the systemd units that run it |
| `rudder/templates/`                          | Files that mention the domain, rendered by the playbook (Firefox's policies)                                                          |
| `vars/main/techniques.yml`                   | How a directive of each Rudder technique is made: its sections and the default of every field                                         |
| `vars/main/policies.yml`                     | The directives (one technique, one list of files or packages each) and the rule that applies them                                     |

`ansible-playbook site.yml --limit kamino` copies the files to the server's
shared folder, creates or updates the directives and rules through the API,
asks the server to generate the policies and **fails if the generation
fails**. A workstation gets them at its next run, or at once with
`sudo rudder agent update && sudo rudder agent run`.

Switching the wallpaper: `-e sw_rudder_wallpaper=red` (or `blue`) on that same
command. The locked setting (`xfce4-desktop.xml`) names one path, and only the
file served at that path changes.

To add a technique to a directive, read its fields in the server's
`/var/rudder/configuration-repository/techniques/<category>/<id>/<version>/metadata.xml`,
and add it to `techniques.yml`. **Send every field**: a component whose fields
are missing is reported `not applicable` and does nothing.

## Locking a setting

XFCE settings are locked in the system defaults the agent drops,
`/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/<channel>.xml`, with
`locked="*"` on each property. The users then cannot change it, in the
settings dialogs or with `xfconf-query`. Tested on the wallpaper.

xfdesktop and xfce4-screensaver only read their settings at start: the
`star-wars-refresh-desktop.path` unit of the workstation watches the files
Rudder drops and restarts both for each open session, one instance at a time
(the old one must be gone before the new one starts). The command and the units
are handed out by Rudder too (directive `star-wars-desktop-refresh`), and the
post-copy command of the directive loads and starts them: Ansible installs
nothing of it, so a workstation needs its agent to have that behaviour.

XFCE brings two screen lockers. `light-locker` locks by itself on idleness,
with LightDM's screen, and ignores the configuration of `xfce4-screensaver`:
the `star-wars-one-screen-locker` directive removes it.

## Things learned

- **The server accepts what the agent rejects.** A directive with a wrong value
  (`hash` for a comparison method) is accepted by the API, and every policy
  generation then fails, leaving the nodes on their old policy without any
  sign. Look in `/var/log/rudder/webapp/webapp.log` (`Policy generation`), and
  in the technique's `metadata.xml` for the allowed values.
- **Creating is a `PUT`, updating a `POST` on the id**, for directives and
  rules. An unknown id answers 500 ("was not found"), not 404.
- **A package installed by hand is not seen at once.** The agent keeps the list
  of installed packages in a cache, and refreshes it after some time. To empty
  it: remove `/var/rudder/cfengine-community/state/packages_installed_apt_get.lmdb`
  (and its two lock files), then run the agent. Files are compared at each run:
  to show a drift being repaired, change a file.
- Files are compared by content (`digest`), not by date: with `mtime`, a file
  replaced by an older one is not copied.

## Plan

1. Per user and per group rules, resolved from the LDAP groups sssd provides:
   the catalogue says who each policy is for.
2. Menus and hidden applications, prohibitions (polkit, permissions).
