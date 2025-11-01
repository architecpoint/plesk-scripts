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

[Learn more →](./mysql-backups)

### Remove Old WordPress Backups

Automatically clean up old WordPress backup files to free up disk space.

**Features:**
- Scans all WordPress installations in Plesk vhosts
- Removes backups older than a specified number of days (default: 365 days)
- Configurable retention period via environment variables
- Safe deletion with proper error handling

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

### MySQL Backup Scripts

**Linux:**
```bash
# Run backup manually
./mysql-backups/mysql-backup.sh

# Schedule with cron (daily at 2 AM)
0 2 * * * /path/to/plesk-scripts/mysql-backups/mysql-backup.sh
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

# Schedule with cron (weekly on Sundays at 3 AM)
0 3 * * 0 /path/to/plesk-scripts/remove-old-wordpress-backups/remove-wordpress-backups.sh
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

## Troubleshooting

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