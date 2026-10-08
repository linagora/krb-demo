# AGENTS.md

Read this first. Follow it exactly. Skipping steps will break the
demo, corrupt the codebase or make the maintainers unhappy.

## Presentation

- krb-demo is an Ansible playbook (`site.yml`) that builds a small
  Kerberos domain on Debian 13: a domain controller (OpenLDAP, MIT
  KDC, LemonLDAP::NG, Twake Directory Manager), a Rudder server that
  configures the workstations, and Linux workstations joined to the
  domain.

- Each component is a role under `roles/`. Workstation configuration
  kept over time is managed by Rudder (`roles/rudder_server`,
  `roles/rudder_agent`, `rudder/`; see `docs/rudder.md`).

- Test in the lab: `lab/lab.sh up`, `lab/lab.sh deploy`, then
  `lab/check.sh` (see `docs/lab.md`).

## Code comments

- Comment only unconventional or tricky code: a non-obvious
  constraint, a workaround, a subtle ordering, a security-relevant
  detail.
- Never paraphrase the code. If the comment restates what the next
  lines do, delete it.
- No project history in comments: no "used to", "replaced the old
  check". Exception: rare cases where the history is required to
  understand why the implementation looks the way it does.
- No design rationale in build files, scripts or config files. Link
  to the relevant documentation instead, if anything.
- When you change code, update or remove the comments around it. An
  obsolete comment is worse than no comment: it misleads reviewers,
  auditors and agents.

## Documentation

- Document architecture choices and feature implementation once, in
  concise Markdown, in the `docs` folder.
- Record significant decisions in a single place; do not duplicate
  them in comments or commits.
- Elsewhere, reference that document rather than repeating its content.
- Playbook variables are documented in `docs/deployment.md`; how
  Rudder's catalogue is built, in `docs/rudder.md`.

## Git commit messages

- Audience: developers.
- A concise subject line, then a short body explaining why when it is
  not obvious. Not a diary, not a copy of the documentation.
- Reference issues/PRs here — this is where history belongs.

## Before submitting

- [ ] Every comment explains something non-obvious and still true.
- [ ] No history, issue numbers or rationale in comments or build
      files.
- [ ] Design changes are documented once, in `docs`.
- [ ] Commit messages are concise and explain why.
