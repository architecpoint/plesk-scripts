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
monitor-cpu-load/                 Sustained CPU load monitor with fail2ban-aware email alerts (AlmaLinux Plesk only)
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

## CI/CD

`.github/workflows/ci.yml` runs two jobs: shellcheck on all `.sh` files, and `.github/scripts/check-self-update.sh`, which verifies every script's self-update block against `.github/self-update.template.sh` (matching core, `SCRIPT_RELATIVE_PATH` equals the file path, unique `UPDATE_CHECK_FILE`). Run both locally before opening a PR.

**Releases:** never tag by hand. `release-pr.yml` opens/updates a "Release vYYYY.MM.DD" PR (renaming `[Unreleased]` in `CHANGELOG.md`) on pushes to `main` that have unreleased entries; merging it triggers `release.yml`, which re-runs shellcheck and the drift check, then creates the tag and release with `SHA256SUMS`. Requires the repo setting *Actions → Allow GitHub Actions to create pull requests*.

## Adding a New Script

1. Create a new top-level folder named after the task.
2. Add a `.sh` (with the self-update block). Add a `.bat` only if the task needs Windows (see the platform-parity rule above).
3. Update `README.md`'s Features section and Scripts table.
4. Update `.github/copilot-instructions.md` if the new script introduces a new convention (env vars, auth pattern, etc.).
5. Run `shellcheck` on any new bash script.

## Documentation

No `docs/` site — `README.md` plus `.github/copilot-instructions.md` are the complete documentation for this repo; a dedicated docs site is not needed for a script collection of this size.

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
- Skipping the README update after a feature change.
