---
description: 'Review rules for Plesk automation scripts'
applyTo: '**'
excludeAgent: ["coding-agent"]
---

# Code review

Shellcheck, the self-update drift check and the docs check run in CI; leave what they catch alone. Review for the judgement calls below.

**Block merge**

- Real credentials, tokens or passwords in a diff. Windows scripts keep `<password_for_mysql>`; Linux scripts use `plesk db`.
- A `rm`, `find ... -delete` or `mysqldump` path that can act outside its intended directory (unquoted or empty variable, glob that widens).
- Windows batch that uses `%var%` where `!var!` is needed, or leaves a path unquoted. Plesk's default path contains parentheses.
- A self-update block edited in one script only. It changes in `.github/self-update.template.sh` first, then everywhere.
- A script that can overlap itself on a schedule, or writes backups, state or reports, without a PID lock or `umask 077`.

**Discuss**

- A feature added to one side of a `.bat`/`.sh` pair that ships both (`mysql-backup`, `pci-dss-scan`) without a note that the Windows version is a subset.
- A behaviour, flag or default changed without the folder `README.md` and header comment following.
- A new script without a folder README, a row in the root README Scripts table, or a Linux-only justification for a missing `.bat`.
- A new term that overlaps one in `GLOSSARY.md`.
- A decision that is hard to reverse and surprising without context but has no ADR.
