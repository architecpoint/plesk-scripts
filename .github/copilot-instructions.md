# Plesk Scripts - GitHub Copilot Instructions

## Project Overview

This is a collection of standalone automation scripts for Plesk server management across Windows and Linux platforms. Scripts are primarily targeted at **Plesk Obsidian** (the current Plesk release line). Each script/folder is **independent** with platform-specific implementations (`.bat` for Windows, `.sh` for Linux). Scripts are designed for ad-hoc execution or scheduled task automation on Plesk hosting control panel servers.

## Architecture Principles

- **One-script-per-task**: Each directory contains a self-contained automation tool
- **Platform support follows the use case**: only `mysql-backup` and `pci-dss-scan` ship both `.bat` and `.sh`; their pairs are kept in step, with the Windows version allowed to be a documented subset. New scripts are Linux-only by default (see `docs/adr/0002-platform-parity-follows-use-case.md`)
- **No build system**: Direct shell/batch script execution, no compilation or bundling required
- **Direct CLI integration**: Windows scripts use `%plesk_dir%` environment variable; Linux scripts use `/usr/sbin/plesk` CLI tool
- **Safety-first design**: validation checks and error handling everywhere; PID locking and `umask 077` where the script can overlap itself or writes sensitive/shared state (see `AGENTS.md` for the per-script table)
- **Security conscious**: Never hardcode credentials; use placeholders (`<password_for_mysql>`) or environment-based auth (`plesk db`)
- **Self-updating bash scripts**: All Linux bash scripts include embedded self-update functionality for automatic updates from GitHub
- **External tool dependency**: Scripts that perform HTTP checks (PCI-DSS scanner) depend on `curl` being available on the system

## Code Conventions

### Windows Batch Scripts

**Standard headers:**
```batch
@echo off
setlocal enabledelayedexpansion
REM Description: Brief purpose of the script
```

**Path handling requirements:**
- **Always use delayed expansion**: Reference variables with `!variable!` instead of `%variable%` to handle parentheses in paths
- **Quote all path references**: Use `"!VARIABLE!"` when referencing paths in commands and conditionals
- **Use `usebackq` in FOR loops**: `for /F "usebackq tokens=*" %%i in ("!FILE!")` to handle quoted filenames with spaces
- **Test with spaces**: Always test with paths containing spaces and parentheses (e.g., `C:\Program Files (x86)\Plesk`)

**Environment variable pattern:**
```batch
if not defined plesk_dir (
    echo ERROR: plesk_dir environment variable is not set
    exit /b 1
)
```

**Error handling:**
```batch
if errorlevel 1 (
    echo ERROR: Operation failed
    exit /b 1
)
```

### Linux Shell Scripts

**Standard headers:**
```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures
# Description: Brief purpose of the script
```

**Self-update pattern** (required for all bash scripts): copy the block from `.github/self-update.template.sh` verbatim (the canonical source; CI fails on drift) and set only `SCRIPT_RELATIVE_PATH` and `UPDATE_CHECK_FILE`. Updates are gated: the script resolves the latest GitHub release (or `UPDATE_VERSION`), downloads the script from that tag, and verifies it against the release's `SHA256SUMS` before installing. See `docs/adr/0001-gated-self-update-from-releases.md`.

**Important self-update implementation notes:**
- Update `SCRIPT_RELATIVE_PATH` to match the script's path in the repository (e.g., `mysql-backups/mysql-backup.sh`)
- Update `UPDATE_CHECK_FILE` with a unique name for each script to avoid conflicts
- Place self-update code immediately after `set -euo pipefail` and before main script logic
- Self-update section should be clearly separated with comment dividers
- Supports `--update` or `--self-update` command-line flags for manual updates
- Supports `AUTO_UPDATE=true` environment variable for automatic updates in cron
- Configurable via `UPDATE_CHECK_INTERVAL` (hours) and `UPDATE_VERSION` (release tag to pin; default latest release) environment variables
- Releases are created by merging the auto-opened "Release vYYYY.MM.DD" PR (`.github/workflows/release-pr.yml`, `release.yml`); never create tags manually

**PID locking pattern** (use when the script can run on a schedule and overlap itself, or writes shared state; see `mysql-backup.sh`):
```bash
PIDFILE="${HOME}/mysql.pid"
if [ -f "${PIDFILE}" ]; then
    echo "Script is already running (PID: $(cat ${PIDFILE}))"
    exit 1
fi
echo $$ > "${PIDFILE}"
trap "rm -f ${PIDFILE}" EXIT
```

**Security - restrictive permissions** (use when the script writes backups, state or reports that may be sensitive):
```bash
umask 077  # Create files with 600 permissions (owner read/write only)
```

**Environment variable pattern:**
```bash
DAYS=${DAYS:-365}  # Default to 365 if not set
FOLDER=${FOLDER:-'/backup/mysql'}  # Default backup location

if [ ! -d "${FOLDER}" ]; then
    echo "ERROR: Backup directory ${FOLDER} does not exist"
    exit 1
fi
```

## Critical Workflows

### MySQL Backup Scripts
- **Windows authentication**: Use placeholder `<password_for_mysql>` that users must replace manually before first run
- **Linux authentication**: Leverage Plesk's built-in `plesk db` command (auto-authenticated with admin credentials)
- **Database filtering**: Always exclude system databases: `information_schema`, `performance_schema`, `phpmyadmin`
- **File naming**: Individual `.sql` files per database using database name as filename
- **Concurrent run prevention**: Linux scripts use PID file locking mechanism

### WordPress Backup Cleanup
- **Path pattern**: Search `/var/www/vhosts/*/wordpress-backups` using glob patterns
- **Retention logic**: Use `DAYS` environment variable (default: 365 days)
- **Validation before deletion**: Check directory existence and file age before removing
- **Safe deletion**: Use `find ... -mtime +${DAYS} -delete` pattern for atomic operations

### Essential Plugin Malware Scanner
- **Platform**: Linux only — scans the Plesk vhosts directory on the server
- **Vhosts root**: Configurable via `WP_VHOSTS_DIR` (default: `/var/www/vhosts`)
- **Detection targets**: 31 affected plugin slugs, `wpos-analytics/` backdoor module, known PHP code signatures (`fetch_ver_info`, `version_info_clean`), `wp-comments-posts.php` dropper, `wp-config.php` infection indicators, and C2 domain (`analytics.essentialplugin.com`) references
- **Output**: Colour-coded per-site status (`CLEAN` / `BACKDOOR PRESENT` / `ACTIVELY COMPROMISED`) plus a plain-text report file for emailing clients
- **Report file**: Configurable via `REPORT_FILE` (default: `/tmp/essential-plugin-scan-<hostname>-<timestamp>.txt`)
- **No Plesk CLI dependency**: Scans the file system directly; does not require `plesk` credentials

### PCI-DSS Security Header Scanner
- **Input**: Requires a target URL as the first argument or via `TARGET_URL` environment variable
- **HTTP checks via curl**: Uses `curl` for all HTTP requests — must be installed on the system
- **Checks performed**: Server/`X-Powered-By` banner disclosure, cookie flag validation (`Secure`, `HttpOnly`, `SameSite`), `Cache-Control` headers on sensitive paths, and additional best-practice headers (`X-Frame-Options`, `HSTS`, `CSP`, etc.)
- **Paths tested**: Homepage, login, checkout, cart, registration, admin, plus custom paths via `EXTRA_PATHS`
- **Exit code**: Equals the number of failures — suitable for CI/CD pipelines
- **Platform parity**: Windows (`pci-dss-scan.bat`) and Linux (`pci-dss-scan.sh`) versions exist; the Linux version has a broader feature set and self-update support

### Monitor Domain Hosting Settings (ASP.NET)
- **Platform**: Windows only — reads from Plesk's MySQL database
- **Authentication**: Uses `%plesk_dir%\MySQL\bin\mysql.exe` with placeholder password `<password_for_mysql>`
- **State tracking**: Stores last known state in `%TEMP%\plesk-monitor\` — only alerts on transitions, no repeated emails
- **Alert types**: ALERT email when ASP.NET transitions enabled → disabled; RESOLVED email on re-enable
- **SMTP**: Configured directly in the script — `SMTP_SERVER`, `SMTP_PORT`, `SMTP_AUTH_USER`, `SMTP_AUTH_PASS`, `SMTP_SECURE` must be set before first run
- **Scheduling**: Designed for Plesk Scheduled Tasks at 15-minute intervals (`0,15,30,45 * * * *`)

## Integration Points

### External Dependencies
- **Plesk CLI**: Windows uses `%plesk_dir%\admin\bin\mysql.exe` (MySQL backups) and `%plesk_dir%\MySQL\bin\mysql.exe` (monitoring); Linux uses `/usr/sbin/plesk`
- **MySQL Client**: Direct `mysql` and `mysqldump` commands for database operations
- **curl**: Required by `pci-dss-scan.sh` and `pci-dss-scan.bat` for all HTTP requests; also used by all Linux self-update functions
- **File System**: Backup paths at `/backup/mysql/`, `%plesk_dir%\Databases\`, `/var/www/vhosts/*/wordpress-backups`; vhosts scanned at `/var/www/vhosts` (configurable)
- **SMTP relay**: `monitor-aspnet.bat` connects to an external SMTP server; configured inside the script

### Authentication Patterns
- **Windows MySQL (backups)**: Manual password replacement in script file (placeholder: `<password_for_mysql>`)
- **Windows MySQL (monitoring)**: Same placeholder pattern — `MYSQL_PASSWORD=<password_for_mysql>` in `monitor-aspnet.bat`
- **Linux MySQL**: Plesk's `plesk db` command (no credentials needed, uses Plesk admin context)
- **File system scanning**: `essential-plugin-scan.sh` reads the file system directly — no database credentials required
- **File permissions**: Linux scripts use `umask 077` to create backups with restrictive permissions (600)

## Maintenance Matrix

When you change... | ...also update
--- | ---
`mysql-backups/mysql-backup.sh` | `mysql-backups/mysql-backup.bat` (platform parity), `README.md` Features/MySQL Backups section
`remove-old-wordpress-backups/remove-wordpress-backups.sh` | `README.md` Features/Remove Old WordPress Backups section (Linux-only, no `.bat` counterpart)
`pci-dss-scan/pci-dss-scan.sh` | `pci-dss-scan/pci-dss-scan.bat` (platform parity, basic-checks subset only), `README.md` PCI-DSS section
`essential-plugin-malware-scan/essential-plugin-scan.sh` | `README.md` Essential Plugin Scanner section (Linux-only, no `.bat` counterpart)
`monitor-domain-hosting/monitor-aspnet.bat` | `README.md` Domain Hosting Monitor section (Windows-only, no `.sh` counterpart)
`monitor-cpu-load/monitor-cpu-load.sh` | `README.md` CPU Load Monitor sections, `GLOSSARY.md` if domain terms change (Linux-only, no `.bat` counterpart)
Any bash script's self-update block | `.github/self-update.template.sh` first (the canonical copy), then every script's copy; only `SCRIPT_RELATIVE_PATH` and `UPDATE_CHECK_FILE` may differ. CI (`.github/scripts/check-self-update.sh`) enforces this. Blocks are copied per script, not shared
Any script's env vars / CLI flags | That script's header comment block and its `README.md` section

## Common Pitfalls

Shared pitfalls (delayed expansion, credentials, PID cleanup, platform parity, README sync) live in `AGENTS.md`. Additional ones:

1. **WSL environment**: User runs on Windows with `wsl.exe` — ensure Linux scripts are bash-compatible and use LF line endings
2. **curl and sha256sum dependency**: the self-update mechanism in all Linux scripts requires `curl` (or `wget` as fallback) and `sha256sum`; `pci-dss-scan.sh` also needs `curl` — document this in script headers and README prerequisites
3. **SMTP configuration**: `monitor-aspnet.bat` requires SMTP settings to be hardcoded before first run — always document all five SMTP variables (`SMTP_SERVER`, `SMTP_PORT`, `SMTP_AUTH_USER`, `SMTP_AUTH_PASS`, `SMTP_SECURE`) in the script header

## Testing & Validation

No automated test suite. Manual validation process:

1. **Shell syntax validation**: Run `shellcheck script.sh` for Linux scripts before committing
2. **Non-production testing**: Test in staging/dev Plesk environment first
3. **Error path testing**: Verify behavior with:
   - Missing credentials (wrong password, no `plesk db` access)
   - Empty databases list
   - Non-existent directories
   - Concurrent script execution (PID locking)
4. **Permission validation**: Check backup files have restrictive permissions (600 on Linux)
5. **Path handling**: Test Windows scripts with spaces and parentheses in paths

## Documentation Standard

### Script Headers
All scripts must include:
```bash
# Purpose: One-line description of what the script does
# Platform: Windows/Linux
# Features:
#   - Feature 1 (e.g., "Excludes system databases")
#   - Feature 2 (e.g., "PID locking prevents concurrent runs")
#   - Self-update capability with automatic or manual updates (Linux only)
# Usage: ./script.sh [--update|--self-update] or script.bat
# Environment Variables:
#   - VAR_NAME: Description (default: value)
#   - AUTO_UPDATE: Set to "true" to enable automatic updates (default: false) [Linux only]
#   - UPDATE_CHECK_INTERVAL: Hours between update checks (default: 24) [Linux only]
#   - UPDATE_VERSION: Release tag to install on update (default: latest release) [Linux only]
# Security: Warning about credentials/placeholders if applicable
```

### README Updates
Whenever scripts are modified or new features are added, update `README.md` to:
- Reflect new features in the Features bullet points for each script
- Add any new configuration options or environment variables
- Update usage examples if command-line parameters or paths change
- Add troubleshooting sections for new functionality or common errors
- Document platform-specific requirements or limitations
