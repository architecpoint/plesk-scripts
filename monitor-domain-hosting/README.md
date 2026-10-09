# Monitor Domain Hosting Settings

Monitors a Plesk hosting setting for one domain and emails an alert when it changes. Currently detects Microsoft ASP.NET being disabled.

## Purpose

Reads the ASP.NET enabled status from the Plesk database (`psa.hosting`), compares it with the last known state, and alerts only on transitions, so there are no repeated emails.

## Platform

Windows only (`monitor-aspnet.bat`). No Linux version.

## Prerequisites

- Windows Plesk server and a user with read access to the Plesk MySQL database (`System` or `Administrator` is typical)
- The Plesk MySQL admin password
- An external SMTP relay (match **Tools & Settings → Mail Server Settings → External SMTP**)

## Usage

```cmd
:: Monitor a domain and alert recipient@example.com if ASP.NET is disabled
monitor-aspnet.bat example.com recipient@example.com
```

## Configuration

Before the first run, edit `monitor-aspnet.bat`: replace the `MYSQL_PASSWORD` placeholder and set the SMTP defaults. Each SMTP value can also be overridden by an environment variable of the same name.

| Variable | Default | Description |
| --- | --- | --- |
| `MYSQL_PASSWORD` | `<password_for_mysql>` | Set in the script: your Plesk MySQL admin password |
| `MYSQL_PORT` | `8306` | Plesk MySQL port (set in the script) |
| `DOMAIN` | none | Domain to monitor; the first argument overrides it |
| `NOTIFY_EMAIL` | none | Alert recipient; the second argument overrides it |
| `SMTP_SERVER` | `mail.example.com` | External SMTP relay hostname |
| `SMTP_PORT` | `25` | Typically `25`, `465` (SSL) or `587` (STARTTLS) |
| `SMTP_AUTH_USER` / `SMTP_AUTH_PASS` | blank | Relay credentials; leave blank if not required |
| `SMTP_SECURE` | blank | `ssl` or `starttls` if required; blank for plain SMTP |
| `SMTP_FROM` | `plesk-monitor@<domain>` | Sender address |
| `STATE_DIR` | `%TEMP%\plesk-monitor` | Directory for state files |

> [!WARNING]
> Never commit real passwords. Keep the `<password_for_mysql>` placeholder in the repository and edit only your server's copy.

**How it works:**

- Each run queries Plesk for the current ASP.NET status and compares it with the last state stored in `%TEMP%\plesk-monitor\`
- An ALERT email is sent only when ASP.NET goes from enabled to disabled
- A RESOLVED email is sent when ASP.NET is re-enabled
- State is stored per domain, so several domains can be monitored with separate scheduled tasks

## Scheduling

Recommended: every 15 minutes with a Plesk Scheduled Task.

1. In Plesk go to **Tools & Settings** → **Scheduled Tasks** → **Add Task**
2. Set **Command** to:

   ```text
   "C:\Scripts\monitor-aspnet.bat" example.com admin@example.com
   ```

   Replace `example.com` and `admin@example.com` with the actual domain and recipient.
3. Set the **Schedule** to `0,15,30,45 * * * *`
4. Run the task as a user with read access to the Plesk MySQL database
5. Click **OK**

## Troubleshooting

**No email arrives**

- Check the five SMTP values above against your Plesk external SMTP settings
- Confirm the relay accepts mail from the server and that the port matches `SMTP_SECURE`

**Repeated or missing alerts**

State lives in `%TEMP%\plesk-monitor\`, which is per user. Make sure the scheduled task always runs as the same account.
