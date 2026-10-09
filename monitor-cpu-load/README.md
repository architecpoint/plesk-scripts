# Monitor Sustained CPU Load

Detects sustained high CPU load on an AlmaLinux Plesk server, finds which subscriptions cause it, and emails an alert. Attacks that fail2ban is already banning don't trigger an alert. Terms are defined in the [glossary](../GLOSSARY.md).

## Purpose

Alerts only on sustained load (by default at least 80% of 5-minute samples above 1.0 × CPU cores across a 30-minute window), attributes CPU to subscriptions, and judges whether fail2ban already handles the attack.

## Platform

Linux only (`monitor-cpu-load.sh`), AlmaLinux Plesk servers, root required. No Windows version.

## Prerequisites

- Run as root
- `plesk` CLI, `fail2ban-client`, and access to the Plesk access logs
- `curl` and `sha256sum` for self-update; `curl` or the local `mail` command for email
- About 30 minutes of collected samples before the first alert is possible

## How it works

- Attributes CPU to Plesk subscriptions through the system user that owns each process
- Analyzes the access logs of the busiest subscriptions for offenders: IPs in any fail2ban jail except `ssh`/`sshd`, plus IPs with a bot-scan pattern (high request rate, many 401/403/404 responses, probe paths)
- Suppresses the alert when banned offenders are at least 80% of the attack traffic, and sends a lower-urgency `[NOTICE]` if load is still high a full window later
- Labels the likely cause: attack-like traffic, web application, database, or other process
- Sends `[ALERT]`, `[REMINDER]` and `[RESOLVED]` HTML emails with an alert cooldown, and writes an incident log
- Read-only: never bans IPs or changes server settings
- Uses a PID lock and `umask 077` for its state files

## Usage

```bash
# See the current analysis without alerting or changing state
./monitor-cpu-load.sh --report > /tmp/cpu-report.html

# Update the script to the latest release
./monitor-cpu-load.sh --update
```

**Reading the results:**

- `[ALERT]`: sustained load that fail2ban is not handling; the email lists CPU per subscription, the busiest offenders (with the jails holding them) and the likely cause
- `[NOTICE]`: fail2ban is banning the attack but load stayed high for another full window
- `[REMINDER]` / `[RESOLVED]`: the incident is still ongoing (every `REMINDER_HOURS`), or load is back to normal

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `EMAIL_TO` | unset | Address that receives alerts (log only if unset) |
| `LOAD_THRESHOLD_FACTOR` | `1.0` | Load threshold as a multiple of CPU cores |
| `WINDOW_MINUTES` / `SAMPLE_INTERVAL_MINUTES` / `SUSTAINED_PERCENT` | `30` / `5` / `80` | Sustained-load rule; the sample interval must match the cron interval |
| `HANDLED_PERCENT` | `80` | Share of attack traffic from banned IPs at which fail2ban counts as handling it |
| `ATTACK_SHARE_PERCENT` | `50` | Share of requests from offenders that makes the load attack-like |
| `ANALYSIS_MINUTES` / `MAX_LOG_LINES` / `TOP_SUBSCRIPTIONS` | `30` / `500000` / `3` | Access log analysis scope |
| `OFFENDER_RPM`, `OFFENDER_BAD_MIN`, `OFFENDER_PROBE_MIN`, `PROBE_PATTERN` | see script header | Heuristics for offenders fail2ban hasn't banned |
| `F2B_EXCLUDE_JAILS` | `ssh sshd` | fail2ban jails ignored when collecting banned IPs |
| `ALERT_COOLDOWN_MINUTES` / `REMINDER_HOURS` | `60` / `6` | Alert pacing |
| `LOG_ROOT` | `/var/www/vhosts/system` | Plesk log root |
| `STATE_DIR` | `/var/lib/plesk-cpu-monitor` | State directory |
| `LOG_FILE` | `/var/log/plesk-cpu-monitor.log` | Incident log |
| `SMTP_SERVER`, `SMTP_PORT`, `SMTP_AUTH_USER`, `SMTP_AUTH_PASS`, `SMTP_SECURE`, `SMTP_FROM` | unset | SMTP relay, same as the [WordPress backup cleanup](../remove-old-wordpress-backups/README.md#configuration); falls back to the local `mail` command |
| `AUTO_UPDATE` / `UPDATE_CHECK_INTERVAL` / `UPDATE_VERSION` | `false` / `24` / latest release | Self-update, see the [root README](../README.md#self-update) |

**Command-line options:**

- `--report`: print the current analysis as HTML; no email, no state change
- `--update` or `--self-update`: update the script to the latest release

## Scheduling

Run as root every 5 minutes from root's crontab or a Plesk Scheduled Task:

```bash
*/5 * * * * EMAIL_TO=ops@example.com SMTP_SERVER=smtp.example.com /root/monitor-cpu-load.sh >/dev/null 2>&1
```

## Troubleshooting

**No alert although the server feels slow**

- Only sustained load alerts: at least `SUSTAINED_PERCENT` (80%) of samples over `WINDOW_MINUTES` (30) must exceed `LOAD_THRESHOLD_FACTOR` × cores
- The first alert comes only after one full window of samples; look for `Collecting samples` in `/var/log/plesk-cpu-monitor.log`
- A `Sustained load is attack-like ... no alert` log line means fail2ban already bans at least `HANDLED_PERCENT` of the attack traffic

**See what the script sees right now**

```bash
./monitor-cpu-load.sh --report > /tmp/cpu-report.html
```

**Email warns that fail2ban could not be checked**

Confirm `fail2ban-client status` works as root. Until it does, the script treats nothing as banned and alerts normally.

**CPU is not attributed to a subscription**

Confirm `plesk db -Ne "SELECT 1"` works as root. Processes run by users without a Plesk subscription are listed as system users.
