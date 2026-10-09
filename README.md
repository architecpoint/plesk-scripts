# Plesk Scripts

Standalone automation scripts for Plesk server administration: MySQL backups, WordPress backup cleanup, PCI-DSS header scanning, WordPress malware scanning, and hosting and CPU monitoring.

⭐ If you like this project, star it on GitHub — it helps a lot!

[Scripts](#scripts) • [Getting Started](#getting-started) • [Self-Update](#self-update) • [Best Practices](#best-practices) • [Security](#security-considerations) • [Contributing](#contributing)

## Overview

Each folder is a self-contained tool you can copy onto a server by itself. Scripts are written for Plesk Obsidian and configured through environment variables, so they need little setup. Linux scripts are bash (`.sh`); Windows scripts are batch (`.bat`). Each folder has its own README with usage, configuration and troubleshooting.

## Scripts

| Script | Platform | Purpose |
| --- | --- | --- |
| [MySQL Backups](./mysql-backups/README.md) | Linux, Windows | Back up every MySQL database to one SQL dump each, excluding system databases |
| [Remove Old WordPress Backups](./remove-old-wordpress-backups/README.md) | Linux | Delete WordPress backups past a retention period, keeping the newest few per domain; optional email report and dry-run |
| [Essential Plugin Scanner](./essential-plugin-malware-scan/README.md) | Linux | Scan WordPress sites for the Essential Plugin supply-chain backdoor and report per-site status |
| [PCI-DSS Scanner](./pci-dss-scan/README.md) | Linux, Windows | Check a website for banner, cookie, cache and security header issues flagged by PCI-DSS scanners |
| [Monitor Domain Hosting Settings](./monitor-domain-hosting/README.md) | Windows | Email an alert when a domain's ASP.NET setting is disabled, and again when it is restored |
| [Monitor Sustained CPU Load](./monitor-cpu-load/README.md) | Linux (AlmaLinux) | Detect sustained CPU load, attribute it to subscriptions, and alert unless fail2ban is already handling the attack |

Only MySQL Backups and the PCI-DSS Scanner ship both Windows and Linux versions. The Windows versions may be a documented subset. New scripts are Linux-only unless the task needs Windows. See [ADR 0002](./docs/adr/0002-platform-parity-follows-use-case.md).

Domain terms (subscription, sustained load, retention, and others) are defined in the [glossary](./GLOSSARY.md).

## Getting Started

### Prerequisites

**Linux scripts:**

- Plesk server (Linux) with shell access
- The `plesk` CLI (`/usr/sbin/plesk`) for scripts that use Plesk's database or settings
- `curl` (or `wget` as a fallback) and `sha256sum` for self-update; the PCI-DSS scanner also needs `curl`

**Windows scripts:**

- Plesk server (Windows) and administrator access
- The Plesk MySQL admin password, for scripts that read the database

### Installation

1. Download the script folder you need, or clone the repository:

   ```bash
   git clone https://github.com/architecpoint/plesk-scripts.git
   cd plesk-scripts
   ```

2. Make Linux scripts executable:

   ```bash
   chmod +x mysql-backups/mysql-backup.sh
   chmod +x remove-old-wordpress-backups/remove-wordpress-backups.sh
   chmod +x pci-dss-scan/pci-dss-scan.sh
   chmod +x essential-plugin-malware-scan/essential-plugin-scan.sh
   chmod +x monitor-cpu-load/monitor-cpu-load.sh
   ```

3. Configure the script as described in its folder README, test it in a non-production environment, then schedule it.

## Self-Update

Every Linux script can update itself from a GitHub release. Updates are gated: the script downloads the file from the release tag and checks it against the release's `SHA256SUMS` before installing. A failed check keeps the current version. See [ADR 0001](./docs/adr/0001-gated-self-update-from-releases.md).

**Manual update:**

```bash
./mysql-backups/mysql-backup.sh --update
```

**Automatic updates (cron):**

```bash
# Enable with an environment variable
AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh

# Daily at 2 AM
0 2 * * * AUTO_UPDATE=true /path/to/plesk-scripts/mysql-backups/mysql-backup.sh
```

**Settings (all Linux scripts):**

| Variable | Default | Description |
| --- | --- | --- |
| `AUTO_UPDATE` | `false` | `true` enables automatic updates |
| `UPDATE_CHECK_INTERVAL` | `24` | Hours between update checks |
| `UPDATE_VERSION` | latest release | Release tag to install, for example `v2026.05.01` |

**How it works:**

1. Each script embeds its own update logic; there is no external dependency.
2. When enabled, it resolves the latest GitHub release (or `UPDATE_VERSION`).
3. It downloads the script from that tag and verifies it against `SHA256SUMS`.
4. The current version is backed up to `<script-name>.backup`.
5. The new version is installed atomically and the script restarts.
6. It runs silently in cron.

### Self-update troubleshooting

**The script cannot download updates**

```bash
# Verify curl or wget is installed
which curl wget

# Test GitHub connectivity
curl -I https://github.com/architecpoint/plesk-scripts/releases/latest
```

**Update checks happen too often**

```bash
# Check every 7 days (168 hours)
UPDATE_CHECK_INTERVAL=168 AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh

# Or disable auto-update and update manually
./mysql-backups/mysql-backup.sh --update
```

**You need a specific version**

```bash
UPDATE_VERSION=v2026.05.01 AUTO_UPDATE=true ./mysql-backups/mysql-backup.sh
```

## Best Practices

1. **Test first.** Run scripts in a non-production environment before deploying.
2. **Use dry-run mode.** Preview deletions with `--dry-run` before running cleanup scripts.
3. **Monitor disk space.** Make sure there is enough storage for database backups.
4. **Verify backups.** Test restoration regularly.
5. **Schedule wisely.** Run backups off-peak.
6. **Review logs.** Check cron logs or Task Scheduler history for run status.
7. **Enable auto-update** in cron jobs, and check `[UPDATE]` log entries to confirm updates succeeded.

## Security Considerations

> [!WARNING]
> These scripts access sensitive server resources. Follow these practices:

- Never commit real passwords. Windows scripts use a `<password_for_mysql>` placeholder that you edit on the server only; Linux scripts use Plesk's `plesk db`.
- Restrict script permissions to authorized users.
- Review script execution logs regularly.
- Keep backup directories access-controlled. Scripts that write backups, state or reports use `umask 077`.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to add or change a script, the checks CI runs, and how releases work.

## License

This project is provided as-is for use with Plesk servers. Please review individual scripts for specific usage terms.
