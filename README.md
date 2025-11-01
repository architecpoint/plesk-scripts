# Plesk Scripts

A collection of utility scripts for automating common Plesk server management tasks, including MySQL database backups and WordPress backup cleanup.

⭐ If you like this project, star it on GitHub — it helps a lot!

[Overview](#overview) • [Scripts](#scripts) • [Getting Started](#getting-started) • [Usage](#usage)

## Overview

This repository provides ready-to-use scripts for Plesk server administrators to automate routine maintenance tasks. Whether you're managing MySQL databases or WordPress installations, these scripts help streamline your server operations with minimal configuration.

**Key Features:**
- MySQL database backup automation for Windows and Linux
- Automated cleanup of old WordPress backup files
- Simple configuration with environment variables
- Compatible with Plesk's built-in tools

## Scripts

### MySQL Backups

Automated MySQL database backup scripts for Plesk servers.

**Available versions:**
- `mysql-backup.bat` - Windows batch script
- `mysql-backup.sh` - Linux shell script

**Features:**
- Backs up all MySQL databases
- Uses Plesk's MySQL credentials
- Creates individual SQL dump files per database
- Excludes system databases (information_schema, performance_schema, phpmyadmin)
- Automatically removes orphaned backup files for deleted databases
- Enhanced error handling and detailed logging
- Success/failure tracking with exit codes
- Self-update capability for automatic script updates

[Learn more →](./mysql-backups)

### Remove Old WordPress Backups

Automatically clean up old WordPress backup files to free up disk space.

**Features:**
- Scans all WordPress installations in Plesk vhosts
- Removes backups older than a specified number of days (default: 365 days)
- Configurable retention period via environment variables
- Safe deletion with proper error handling
- Detailed logging with timestamps
- Exit codes for automation and monitoring
- Self-update capability for automatic script updates

[Learn more →](./remove-old-wordpress-backups)

## Getting Started

### Prerequisites

**For Linux scripts:**
- Plesk server (Linux)
- Shell access with appropriate permissions
- `plesk` CLI tool available

**For Windows scripts:**
- Plesk server (Windows)
- Administrator access
- MySQL admin password

### Installation

1. Clone this repository or download the scripts you need:
   ```bash
   git clone https://github.com/architecpoint/plesk-scripts.git
   cd plesk-scripts
   ```

2. Make scripts executable (Linux only):
   ```bash
   chmod +x mysql-backups/mysql-backup.sh
   chmod +x remove-old-wordpress-backups/remove-wordpress-backups.sh
   ```

3. Configure the scripts according to your environment (see individual script documentation).

## Usage

### Self-Update Feature

All Linux scripts include built-in self-update capability to ensure you're always running the latest version from GitHub.

**Manual update:**
```bash
# Update the script to the latest version
./mysql-backups/mysql-backup.sh --update
./remove-old-wordpress-backups/remove-wordpress-backups.sh --update
```

**Automatic updates (recommended for cron):**
```bash
# Enable auto-update with environment variable
AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh

# Configure in cron for automatic updates
0 2 * * * AUTO_UPDATE=true /path/to/plesk-scripts/mysql-backups/mysql-backup.sh
```

**Configuration:**
- `AUTO_UPDATE` - Set to `true` to enable automatic updates (default: `false`)
- `UPDATE_CHECK_INTERVAL` - Hours between update checks (default: `24`)
- `GITHUB_BRANCH` - GitHub branch to update from (default: `main`)

**How it works:**
1. Each script contains embedded self-update functionality (no external dependencies)
2. When enabled, scripts check for updates from the GitHub repository
3. If a newer version is found, it's downloaded and validated
4. The current version is backed up to `<script-name>.backup`
5. The new version is installed atomically
6. The script restarts automatically with the updated version
7. Works silently in cron with no user interaction required

### MySQL Backup Scripts

**Linux:**
```bash
# Run backup manually
./mysql-backups/mysql-backup.sh

# Run backup with auto-update enabled
AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh

# Schedule with cron (daily at 2 AM with auto-update)
0 2 * * * AUTO_UPDATE=true /path/to/plesk-scripts/mysql-backups/mysql-backup.sh
```

**Windows:**
```cmd
# Update the script with your MySQL admin password first
# Then run manually or schedule with Task Scheduler
mysql-backups\mysql-backup.bat
```

> [!NOTE]
> For Windows, you must replace `<password_for_mysql>` in the batch file with your actual MySQL admin password before running.

### Remove Old WordPress Backups

```bash
# Run with default settings (removes backups older than 365 days)
./remove-old-wordpress-backups/remove-wordpress-backups.sh

# Run with custom retention period (e.g., 180 days)
DAYS=180 ./remove-old-wordpress-backups/remove-wordpress-backups.sh

# Run with auto-update enabled
AUTO_UPDATE=true ./remove-old-wordpress-backups/remove-wordpress-backups.sh

# Schedule with cron (weekly on Sundays at 3 AM with auto-update)
0 3 * * 0 AUTO_UPDATE=true /path/to/plesk-scripts/remove-old-wordpress-backups/remove-wordpress-backups.sh
```

## Configuration

### MySQL Backup Configuration

**Linux (`mysql-backup.sh`):**
- Backup location: `/backup/mysql/data/`
- Automatically uses Plesk database credentials

**Windows (`mysql-backup.bat`):**
- Backup location: `%plesk_dir%\Databases\MySQL\backup\`
- Requires manual MySQL password configuration

### WordPress Backup Cleanup Configuration

Set the `DAYS` environment variable to customize the retention period:
- Default: `365` days
- Example: `DAYS=180` keeps backups for 6 months

## Best Practices

1. **Test scripts first** - Always test scripts in a non-production environment before deploying
2. **Monitor disk space** - Ensure adequate storage for database backups
3. **Verify backups** - Regularly test backup restoration procedures
4. **Schedule wisely** - Run backups during off-peak hours to minimize server load
5. **Review logs** - Check cron logs or Task Scheduler history for script execution status
6. **Enable auto-update** - Set `AUTO_UPDATE=true` in cron jobs to keep scripts up-to-date automatically
7. **Check update logs** - Review `[UPDATE]` log entries to confirm successful updates

## Troubleshooting

### Self-Update Issues

**Problem:** Script cannot download updates
```bash
# Verify curl or wget is installed
which curl wget

# Test GitHub connectivity
curl -I https://raw.githubusercontent.com/architecpoint/plesk-scripts/main/README.md
```

**Problem:** Update check happens too frequently
```bash
# Increase check interval to 7 days (168 hours)
UPDATE_CHECK_INTERVAL=168 AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh

# Or disable auto-update and use manual updates
./mysql-backups/mysql-backup.sh --update
```

**Problem:** Script updated but using wrong branch
```bash
# Specify branch explicitly (e.g., develop, main)
GITHUB_BRANCH=develop AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh
```

### MySQL Backup Issues

**Problem:** Script cannot connect to MySQL
```bash
# Verify Plesk database access
plesk db -e "show databases"
```

**Problem:** Permission denied
```bash
# Ensure script has execute permissions
chmod +x mysql-backup.sh
```

### WordPress Backup Cleanup Issues

**Problem:** Files not being deleted
- Check the backup path exists: `/var/www/vhosts/*/wordpress-backups`
- Verify file permissions for the script user
- Ensure correct `DAYS` value is set

## Security Considerations

> [!WARNING]
> These scripts access sensitive server resources. Follow these security best practices:

- Store MySQL passwords securely (use environment variables or secure configuration files)
- Restrict script permissions to authorized users only
- Regularly review and audit script execution logs
- Ensure backup directories have appropriate access controls

## Contributing

Contributions are welcome! If you have improvements or additional scripts for Plesk management:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is provided as-is for use with Plesk servers. Please review individual scripts for specific usage terms.