# AGENTS.md

## Project Overview

`plesk-scripts` is a collection of independent, standalone automation scripts for Plesk server administration (MySQL backups, WordPress backup cleanup, PCI-DSS header scanning, WordPress malware scanning, ASP.NET hosting monitoring). There is no shared runtime, package manager, or build system — every top-level folder is a self-contained tool with platform-specific implementations (`.bat` for Windows, `.sh` for Linux). Each folder's `README.md` documents that script; `CONTRIBUTING.md` holds the coding conventions, testing, CI and release process; `GLOSSARY.md` defines domain terms.

## Repository Structure

```
mysql-backups/                    MySQL backup automation (Windows + Linux)
remove-old-wordpress-backups/     WordPress backup retention cleanup (Linux)
pci-dss-scan/                     PCI-DSS security header compliance scanner (Windows + Linux)
essential-plugin-malware-scan/    WordPress supply-chain backdoor scanner (Linux only)
monitor-domain-hosting/           ASP.NET hosting setting monitor + email alerts (Windows only)
monitor-cpu-load/                 Sustained CPU load monitor with fail2ban-aware email alerts (AlmaLinux Plesk only)
.github/instructions/             Path-scoped Copilot instructions (bash, markdown, CentOS/RHEL, GitHub Actions, commenting, docs sync)
.github/agents/, .github/skills/  Custom Copilot agents and skills
<folder>/README.md                Per-script usage, configuration and troubleshooting — must stay in sync with the script
README.md                         Index of scripts plus shared install, self-update and security notes
CONTRIBUTING.md                   Contributor guide: conventions, testing, CI, releases, adding a script
GLOSSARY.md, docs/adr/            Domain terms and design decisions
```

## Tech Stack

- **Linux**: Bash (`.sh`), targeting Plesk Obsidian's `/usr/sbin/plesk` CLI and MySQL client tools.
- **Windows**: Batch (`.bat`), targeting `%plesk_dir%` and `mysql.exe`.
- No package manager, no dependency manifest, no build step — scripts run directly.

## Build & Run

There is no install/build step. Run a script directly:

```bash
./mysql-backups/mysql-backup.sh
```

```batch
mysql-backups\mysql-backup.bat
```

Most Linux scripts support `AUTO_UPDATE=true` and manual `--update`/`--self-update` flags for self-updating from GitHub (see the self-update block in `CONTRIBUTING.md`).

## Testing

Write and change files with the edit/create tools; use bash only to run programs.

No automated test suite for the data-handling scripts. Lint every changed bash script with `shellcheck path/to/script.sh`, and run the checks in `CONTRIBUTING.md` → **Testing** before opening a PR.

## Key Patterns and Conventions

- **Platform parity**: only scripts that already ship both versions (`mysql-backup`, `pci-dss-scan`) keep their `.bat`/`.sh` pair in step, and the README notes any subset. New scripts are Linux-only by default ([ADR 0002](docs/adr/0002-platform-parity-follows-use-case.md)).
- **Standalone scripts**: each script is a single file that works when copied onto a server by itself; never source shared code.
- **Self-update block**: every Linux bash script embeds its own copy of the self-update functions immediately after `set -euo pipefail`. Copy it from `.github/self-update.template.sh` and change only `SCRIPT_RELATIVE_PATH` and `UPDATE_CHECK_FILE`; CI fails if a copy drifts. Updates are gated: they install only a GitHub release verified against its `SHA256SUMS` ([ADR 0001](docs/adr/0001-gated-self-update-from-releases.md)); `UPDATE_VERSION` pins a tag.
- **PID locking**: required when the script can run on a schedule and overlap itself, or writes shared state (`mysql-backup.sh`, `monitor-cpu-load.sh`). Use a PID file + `trap ... EXIT`. Read-only scanners don't need it.
- **Restrictive permissions (`umask 077`)**: required when the script writes backups, state files or reports that may contain sensitive data.
- **Security**: never hardcode credentials — Windows scripts use a `<password_for_mysql>` placeholder; Linux scripts use Plesk's `plesk db` command.

| Script | PID lock | `umask 077` |
| --- | --- | --- |
| `mysql-backups/mysql-backup.sh` | yes | yes |
| `monitor-cpu-load/monitor-cpu-load.sh` | yes | yes |
| `remove-old-wordpress-backups/remove-wordpress-backups.sh` | no | no |
| `pci-dss-scan/pci-dss-scan.sh` | no | no |
| `essential-plugin-malware-scan/essential-plugin-scan.sh` | no | no |

- **System DB exclusion**: MySQL scripts always filter `information_schema`, `performance_schema`, `phpmyadmin`.

## Maintenance Matrix

When you change... | ...also update
--- | ---
`mysql-backups/mysql-backup.sh` | `mysql-backups/mysql-backup.bat` (platform parity), `mysql-backups/README.md`
`remove-old-wordpress-backups/remove-wordpress-backups.sh` | `remove-old-wordpress-backups/README.md` (Linux-only)
`pci-dss-scan/pci-dss-scan.sh` | `pci-dss-scan/pci-dss-scan.bat` (basic-checks subset only), `pci-dss-scan/README.md`
`essential-plugin-malware-scan/essential-plugin-scan.sh` | `essential-plugin-malware-scan/README.md` (Linux-only)
`monitor-domain-hosting/monitor-aspnet.bat` | `monitor-domain-hosting/README.md` (Windows-only)
`monitor-cpu-load/monitor-cpu-load.sh` | `monitor-cpu-load/README.md`, `GLOSSARY.md` if domain terms change (Linux-only)
Any bash script's self-update block | `.github/self-update.template.sh` first, then every script's copy; only `SCRIPT_RELATIVE_PATH` and `UPDATE_CHECK_FILE` may differ. CI enforces this
Any script's env vars / CLI flags | That script's header comment block and the env var table in its folder `README.md`
A new script | Root `README.md` Scripts table, the table above, and the PID lock / `umask 077` table

## CI and Releases

CI runs shellcheck, the self-update drift check, the self-update test and actionlint; run the first three and `.github/scripts/check-docs.sh` locally. Never tag releases by hand — merging the auto-opened "Release vYYYY.MM.DD" PR does it. Details are in `CONTRIBUTING.md` → **CI** and **Releases**.

## Adding a New Script

Follow `CONTRIBUTING.md` → **Adding a new script**.

## Documentation

Docs live in `README.md`, one `README.md` per script folder, `CONTRIBUTING.md`, `GLOSSARY.md` and `docs/adr/` ([ADR 0003](docs/adr/0003-per-script-readmes.md)). There is no docs site; it isn't needed for a collection of this size.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `architecpoint/plesk-scripts` (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Common Pitfalls

- Forgetting delayed expansion (`!VAR!`) in batch scripts breaks on Plesk's default path with parentheses.
- Adding a feature to only one side of a `.bat`/`.sh` pair.
- Committing real MySQL/SMTP passwords instead of placeholders.
- Forgetting `trap "rm -f ${PIDFILE}" EXIT`, leaving stale PID locks.
- Skipping the folder README update after a feature change.

- WSL: the maintainer edits through `wsl.exe`, so keep Linux scripts bash-compatible with LF line endings.
- The self-update block needs `curl` (or `wget`) and `sha256sum`; document these, and `curl` for `pci-dss-scan.sh`, in script headers and folder README prerequisites.
- `monitor-aspnet.bat` needs all five SMTP variables set in the script before first run; document them in its header.
