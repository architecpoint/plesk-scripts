# MySQL Backups

Backs up every MySQL database on a Plesk server to individual SQL dump files.

## Purpose

Creates one `.sql` dump per database, excludes system databases (`information_schema`, `performance_schema`, `phpmyadmin`), and removes orphaned dumps for databases that no longer exist.

## Platform

| Script | Platform | Notes |
| --- | --- | --- |
| `mysql-backup.sh` | Linux | PID locking, `umask 077`, self-update |
| `mysql-backup.bat` | Windows | Documented subset: no PID lock or self-update |

## Prerequisites

- **Linux:** the `plesk` CLI (`/usr/sbin/plesk`), `mysqldump`, and `curl` plus `sha256sum` for self-update. No credentials needed: the script uses `plesk db`.
- **Windows:** administrator access and the Plesk MySQL admin password. Replace the `<password_for_mysql>` placeholder in `mysql-backup.bat` before the first run.

## Usage

**Linux:**

```bash
# Run a backup manually
./mysql-backup.sh

# Run with auto-update enabled
AUTO_UPDATE=true ./mysql-backup.sh

# Update the script to the latest release
./mysql-backup.sh --update
```

**Windows:**

```cmd
mysql-backup.bat
```

> [!NOTE]
> On Windows, replace `<password_for_mysql>` in the batch file with your MySQL admin password before running.

## Configuration

| Item | Linux | Windows |
| --- | --- | --- |
| Backup location | `/backup/mysql/data/` | `%plesk_dir%\Databases\MySQL\backup\` |
| Credentials | Plesk's `plesk db` (automatic) | Manual password in the script |

Linux environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `AUTO_UPDATE` | `false` | Set to `true` to update automatically |
| `UPDATE_CHECK_INTERVAL` | `24` | Hours between update checks |
| `UPDATE_VERSION` | latest release | Release tag to install on update |

See the [root README](../README.md#self-update) for how self-update works.

## Scheduling

```bash
# Daily at 2 AM with auto-update (cron)
0 2 * * * AUTO_UPDATE=true /path/to/plesk-scripts/mysql-backups/mysql-backup.sh
```

On Windows, use Task Scheduler (or a Plesk Scheduled Task) to run `mysql-backup.bat`.

The Linux script's PID lock prevents overlapping runs.

## Troubleshooting

**Script cannot connect to MySQL**

```bash
# Verify Plesk database access
plesk db -e "show databases"
```

**Permission denied**

```bash
chmod +x mysql-backup.sh
```

**Script reports it is already running**

A previous run is still active. The lock file is `/backup/mysql/mysql.pid`. A stale lock (the recorded process is gone) is detected and removed automatically on the next run.
