# AGENTS.md

## Project Overview

`plesk-scripts` is a collection of independent, standalone automation scripts for Plesk server administration (MySQL backups, WordPress backup cleanup, PCI-DSS header scanning, WordPress malware scanning, ASP.NET hosting monitoring). There is no shared runtime, package manager, or build system — every top-level folder is a self-contained tool with platform-specific implementations (`.bat` for Windows, `.sh` for Linux). See `.github/copilot-instructions.md` for the full architecture, per-script feature breakdown, and coding conventions.

## Repository Structure

```
mysql-backups/                    MySQL backup automation (Windows + Linux)
remove-old-wordpress-backups/     WordPress backup retention cleanup (Linux)
pci-dss-scan/                     PCI-DSS security header compliance scanner (Windows + Linux)
essential-plugin-malware-scan/    WordPress supply-chain backdoor scanner (Linux only)
monitor-domain-hosting/           ASP.NET hosting setting monitor + email alerts (Windows only)
.github/instructions/             Path-scoped Copilot instructions (shell, PowerShell, markdown, security, etc.)
.github/agents/, .github/skills/  Custom Copilot agents and skills
README.md                         User-facing docs — must stay in sync with script features
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

Most Linux scripts support `AUTO_UPDATE=true` and manual `--update`/`--self-update` flags for self-updating from GitHub (see the self-update pattern in `.github/copilot-instructions.md`).

## Testing

No automated test suite. Validation is manual:

- Lint every changed bash script: `shellcheck path/to/script.sh`
- Test in a staging/dev Plesk environment before merging — many scripts assume Plesk CLI/MySQL credentials are present.
- For Windows scripts, test with paths containing spaces and parentheses (e.g. `C:\Program Files (x86)\Plesk`).
- See `.github/copilot-instructions.md` → **Testing & Validation** for the full manual checklist (missing credentials, empty DB lists, concurrent runs, permission checks).

## Key Patterns and Conventions

- **Platform parity**: paired `.bat`/`.sh` scripts must both be updated when a feature changes (single-platform scripts like `essential-plugin-scan.sh` and `monitor-aspnet.bat` are exempt).
- **Self-update block**: every Linux bash script embeds the self-update functions immediately after `set -euo pipefail` (see `.github/copilot-instructions.md` for the full template) — update `SCRIPT_RELATIVE_PATH` and `UPDATE_CHECK_FILE` per script.
- **PID locking**: long-running Linux scripts (e.g. `mysql-backup.sh`) use a PID file + `trap ... EXIT` to prevent concurrent runs.
- **Security**: never hardcode credentials — Windows scripts use a `<password_for_mysql>` placeholder; Linux scripts use Plesk's `plesk db` command; backups use `umask 077`.
- **System DB exclusion**: MySQL scripts always filter `information_schema`, `performance_schema`, `phpmyadmin`.

## CI/CD

No CI currently existed prior to this change — see `.github/workflows/ci.yml` (shellcheck on changed `.sh` files) added alongside this file.

## Adding a New Script

1. Create a new top-level folder named after the task.
2. Add `.sh` (with the self-update block) and/or `.bat` implementation per the platform-parity rule above.
3. Update `README.md`'s Features section and Scripts table.
4. Update `.github/copilot-instructions.md` if the new script introduces a new convention (env vars, auth pattern, etc.).
5. Run `shellcheck` on any new bash script.

## Documentation

No `docs/` site — `README.md` plus `.github/copilot-instructions.md` are the complete documentation for this repo; a dedicated docs site is not needed for a script collection of this size.

## Common Pitfalls

- Forgetting delayed expansion (`!VAR!`) in batch scripts breaks on Plesk's default path with parentheses.
- Adding a feature to only one side of a `.bat`/`.sh` pair.
- Committing real MySQL/SMTP passwords instead of placeholders.
- Forgetting `trap "rm -f ${PIDFILE}" EXIT`, leaving stale PID locks.
- Skipping the README update after a feature change.
