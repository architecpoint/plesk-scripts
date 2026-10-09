# Remove Old WordPress Backups

Cleans up old WordPress backup files on a Plesk server to free disk space.

## Purpose

Scans `/var/www/vhosts/*/wordpress-backups`, removes backups older than a retention period, and always keeps a minimum number of the newest backups per domain.

## Platform

Linux only (`remove-wordpress-backups.sh`). No Windows version.

## Prerequisites

- Linux Plesk server with shell access to the vhosts directory
- `curl` and `sha256sum` for self-update (and for SMTP relay email)
- The `mail` command, only if you email reports without an SMTP relay

## Usage

```bash
# Preview deletions without removing anything
./remove-wordpress-backups.sh --dry-run

# Run with defaults (remove backups older than 365 days, keep at least 3 per domain)
./remove-wordpress-backups.sh

# Custom retention period
DAYS=180 ./remove-wordpress-backups.sh

# Preview a custom retention period before deleting
DAYS=180 ./remove-wordpress-backups.sh --dry-run

# Always keep the 5 newest backups per domain, even if older than DAYS
MIN_KEEP=5 ./remove-wordpress-backups.sh

# Email a per-domain report (requires the 'mail' command)
EMAIL_TO="admin@example.com" ./remove-wordpress-backups.sh

# Email the report via an SMTP relay when no local MTA is available (uses curl)
EMAIL_TO="admin@example.com" SMTP_SERVER="mail.example.com" SMTP_PORT=587 SMTP_SECURE=starttls \
  SMTP_AUTH_USER="relay-user" SMTP_AUTH_PASS="relay-pass" \
  ./remove-wordpress-backups.sh

# Run with auto-update enabled
AUTO_UPDATE=true ./remove-wordpress-backups.sh
```

## Configuration

**Environment variables:**

| Variable | Default | Description |
| --- | --- | --- |
| `DAYS` | `365` | Days to keep backups. `DAYS=180` keeps six months |
| `MIN_KEEP` | `3` | Newest backups always kept per domain, regardless of age |
| `DRY_RUN` | `false` | `true` previews deletions without removing files |
| `EMAIL_TO` | unset | Address for the per-domain HTML report (no email if unset) |
| `EMAIL_SUBJECT` | `WordPress Backup Cleanup Report - <hostname>` | Report subject line |
| `EMAIL_ONLY_ON_DELETIONS` | `false` | `true` skips the email when nothing was deleted |
| `SMTP_SERVER` | unset | SMTP relay host. When set, mail is sent via `curl` and takes priority over the local `mail` command |
| `SMTP_PORT` | `25` | SMTP relay port |
| `SMTP_AUTH_USER` / `SMTP_AUTH_PASS` | unset | Relay credentials; leave unset for an unauthenticated relay |
| `SMTP_SECURE` | blank | Blank for plain, `ssl` for implicit TLS (usually port 465), `starttls` for STARTTLS (usually port 587) |
| `SMTP_FROM` | `plesk-monitor@<hostname>` | Sender address |
| `AUTO_UPDATE` | `false` | `true` enables automatic updates |
| `UPDATE_CHECK_INTERVAL` | `24` | Hours between update checks |
| `UPDATE_VERSION` | latest release | Release tag to install on update |

The report contains a summary with total disk space, the backups removed (or that would be removed in dry-run) per domain with filenames, dates and sizes, and a backups-found table per domain with newest and oldest dates and disk space used.

**Command-line options:**

- `--dry-run` or `-n`: preview deletions without removing files
- `--update` or `--self-update`: update the script to the latest release

See the [root README](../README.md#self-update) for how self-update works.

## Scheduling

```bash
# Weekly on Sundays at 3 AM with auto-update (cron)
0 3 * * 0 AUTO_UPDATE=true /path/to/plesk-scripts/remove-old-wordpress-backups/remove-wordpress-backups.sh
```

Run with `--dry-run` first on any new server. The script does not use PID locking.

## Troubleshooting

**You want to see what will be deleted first**

```bash
./remove-wordpress-backups.sh --dry-run
# or
DRY_RUN=true ./remove-wordpress-backups.sh
```

**Files are not being deleted**

- Check that `/var/www/vhosts/*/wordpress-backups` exists
- Verify file permissions for the user running the script
- Check the `DAYS` value; the newest `MIN_KEEP` backups per domain are never deleted
- Run with `--dry-run` to see what is eligible
