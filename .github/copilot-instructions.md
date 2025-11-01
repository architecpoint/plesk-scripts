# Plesk Scripts - AI Agent Instructions

This repository contains utility scripts for Plesk server automation. Scripts are organized by task with dual platform support (Windows `.bat` and Linux `.sh`).

## Architecture Overview

- **Script Organization**: Each automation task lives in its own directory with platform-specific implementations
- **Target Environment**: Plesk hosting control panel on Windows or Linux servers
- **No Build System**: Direct shell/batch script execution, no compilation or bundling required

## Key Patterns

### Dual Platform Support
Scripts come in pairs: `.bat` (Windows) and `.sh` (Linux). When modifying functionality:
- Update both versions to maintain feature parity
- Windows scripts use `%plesk_dir%` environment variable for Plesk paths
- Linux scripts use hardcoded `/usr/sbin/plesk` CLI tool and `/backup/` paths

### Security-Sensitive Credentials
- **Windows MySQL scripts**: Use placeholder `<password_for_mysql>` that users must replace manually
- **Linux MySQL scripts**: Leverage Plesk's built-in `plesk db` command (auto-authenticated)
- Never hardcode actual credentials; always use placeholders or environment-based auth

### Script Safety Mechanisms
- **PID locking** (Linux): `mysql-backup.sh` uses PID file at `${HOME}/mysql.pid` to prevent concurrent runs
- **Validation before action**: Check environment variables, directory existence before executing destructive operations
- **Error handling**: Exit codes (`exit /b 1` for .bat, `exit 1` for .sh) and error messages to stderr

### File Naming and Paths
- **MySQL backups**: Individual `.sql` files per database (e.g., `database_name.sql`)
- **System databases excluded**: `information_schema`, `performance_schema`, `phpmyadmin` filtered out
- **WordPress backups**: Searches `/var/www/vhosts/*/wordpress-backups` using glob patterns

## Environment Variables

- `DAYS`: Retention period for WordPress backup cleanup (default: 365)
- `plesk_dir`: Windows Plesk installation path (system-provided)
- Custom backup paths should use `HOME` and `FOLDER` variables (see `mysql-backup.sh`)

## Testing & Validation

No automated test suite. When modifying scripts:
1. Validate shell syntax: `shellcheck script.sh` for Linux scripts
2. Test in non-production Plesk environment first
3. Verify both success and error paths (missing credentials, no databases, etc.)
4. Check that backup files are created with restrictive permissions (`umask 077`)

## Common Modifications

**Adding new backup types**: Create new directory, include both `.bat` and `.sh`, follow existing error handling patterns
**Changing retention logic**: Modify `DAYS` default or add new env vars (document in script comments and README)
**Path customization**: Update hardcoded paths (`/backup/mysql/`, `%plesk_dir%\Databases`) at top of scripts for easy configuration
**Feature additions**: When adding new features to scripts, always update the README.md to document the changes in the relevant Features section

## Documentation Standard

Script headers must include:
- Purpose and features
- Platform (Windows/Linux)
- Security warnings (e.g., password placeholders)
- Usage examples with environment variables

**README Updates**: Whenever scripts are modified or new features are added, update README.md to:
- Reflect new features in the Features bullet points
- Add any new configuration options
- Update usage examples if command-line parameters change
- Add troubleshooting sections for new functionality
