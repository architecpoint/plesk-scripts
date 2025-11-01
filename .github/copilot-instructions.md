# Plesk Scripts - GitHub Copilot Instructions

## Project Overview

This is a collection of standalone automation scripts for Plesk server management across Windows and Linux platforms. Each script/folder is **independent** with platform-specific implementations (`.bat` for Windows, `.sh` for Linux). Scripts are designed for ad-hoc execution or scheduled task automation on Plesk hosting control panel servers.

## Architecture Principles

- **One-script-per-task**: Each directory contains a self-contained automation tool
- **Dual platform support**: Scripts come in pairs (`.bat` and `.sh`) with feature parity
- **No build system**: Direct shell/batch script execution, no compilation or bundling required
- **Direct CLI integration**: Windows scripts use `%plesk_dir%` environment variable; Linux scripts use `/usr/sbin/plesk` CLI tool
- **Safety-first design**: PID locking, validation checks, and error handling to prevent concurrent runs and data loss
- **Security conscious**: Never hardcode credentials; use placeholders (`<password_for_mysql>`) or environment-based auth (`plesk db`)

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

**PID locking pattern** (see `mysql-backup.sh`):
```bash
PIDFILE="${HOME}/mysql.pid"
if [ -f "${PIDFILE}" ]; then
    echo "Script is already running (PID: $(cat ${PIDFILE}))"
    exit 1
fi
echo $$ > "${PIDFILE}"
trap "rm -f ${PIDFILE}" EXIT
```

**Security - restrictive permissions:**
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

## Integration Points

### External Dependencies
- **Plesk CLI**: Windows uses `%plesk_dir%\admin\bin\mysql.exe`, Linux uses `/usr/sbin/plesk`
- **MySQL Client**: Direct `mysql` and `mysqldump` commands for database operations
- **File System**: Backup paths at `/backup/mysql/`, `%plesk_dir%\Databases\`, `/var/www/vhosts/*/wordpress-backups`

### Authentication Patterns
- **Windows MySQL**: Manual password replacement in script file (placeholder: `<password_for_mysql>`)
- **Linux MySQL**: Plesk's `plesk db` command (no credentials needed, uses Plesk admin context)
- **File permissions**: Linux scripts use `umask 077` to create backups with restrictive permissions (600)

## Key Files/Directories

- **`mysql-backups/`**: Database backup automation for Windows and Linux
  - `mysql-backup.bat`: Windows implementation with manual password configuration
  - `mysql-backup.sh`: Linux implementation with PID locking and Plesk CLI integration
- **`remove-old-wordpress-backups/`**: WordPress backup retention management
  - `remove-wordpress-backups.sh`: Linux script for cleaning old WordPress backup files
- **`README.md`**: User-facing documentation (must be updated when features change)

## Common Pitfalls

1. **Windows path handling**: Forgetting delayed expansion causes failures with Plesk's default path `C:\Program Files (x86)\Plesk`
2. **Credential security**: Never commit actual MySQL passwords; always use placeholders or environment-based auth
3. **PID file cleanup**: Ensure `trap "rm -f ${PIDFILE}" EXIT` is set to prevent stale locks
4. **Platform parity**: When adding features, update **both** `.bat` and `.sh` versions
5. **System database inclusion**: Always filter out `information_schema`, `performance_schema`, `phpmyadmin` in MySQL scripts
6. **README sync**: Feature additions require README.md updates in the Features section
7. **WSL environment**: User runs on Windows with `wsl.exe` - ensure Linux scripts are bash-compatible and use LF line endings

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
# Usage: ./script.sh or script.bat
# Environment Variables:
#   - VAR_NAME: Description (default: value)
# Security: Warning about credentials/placeholders if applicable
```

### README Updates
Whenever scripts are modified or new features are added, update `README.md` to:
- Reflect new features in the Features bullet points for each script
- Add any new configuration options or environment variables
- Update usage examples if command-line parameters or paths change
- Add troubleshooting sections for new functionality or common errors
- Document platform-specific requirements or limitations
