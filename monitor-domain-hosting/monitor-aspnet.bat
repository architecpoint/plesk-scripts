@echo off
REM ============================================================================
REM Purpose: Monitor Microsoft ASP.NET hosting setting for a Plesk domain and
REM          send email alerts when the status changes
REM Platform: Windows
REM Features:
REM   - Reads ASP.NET enabled status directly from the Plesk database (psa.hosting)
REM   - Tracks state between runs - only alerts on change (no duplicate alerts)
REM   - Sends ALERT email when ASP.NET becomes disabled
REM   - Sends RESOLVED email when ASP.NET is re-enabled after being disabled
REM   - Suitable for Plesk Scheduled Tasks (run every 5-15 minutes)
REM Usage: monitor-aspnet.bat <domain> <recipient_email>
REM Environment Variables:
REM   - DOMAIN: Domain to monitor (overridden by first argument)
REM   - NOTIFY_EMAIL: Alert recipient address (overridden by second argument)
REM   - SMTP_SERVER: Override SMTP hostname (default: configured in script)
REM   - SMTP_PORT: Override SMTP port (default: configured in script)
REM   - SMTP_AUTH_USER: Override SMTP username (default: configured in script)
REM   - SMTP_AUTH_PASS: Override SMTP password (default: configured in script)
REM   - SMTP_SECURE: Override SMTP security - blank/ssl/starttls (default: configured in script)
REM   - SMTP_FROM: Sender address (default: plesk-monitor@<domain>)
REM   - STATE_DIR: Directory for state files (default: %TEMP%\plesk-monitor)
REM   - MYSQL_PORT: Plesk MySQL port (default: 8306)
REM Security: Replace <password_for_mysql> with the Plesk MySQL admin password before running
REM
REM Plesk Scheduled Tasks setup (every 15 minutes):
REM   Tools & Settings > Scheduled Tasks > Add Task
REM   Command: "C:\Scripts\monitor-aspnet.bat" example.com admin@example.com
REM   Schedule: 0,15,30,45 * * * *
REM ============================================================================
setlocal enabledelayedexpansion

REM ============================================================================
REM VALIDATE ENVIRONMENT
REM ============================================================================

if not defined plesk_dir (
    echo ERROR: plesk_dir environment variable is not set.
    echo Please ensure Plesk is installed and the environment is configured.
    exit /b 1
)

set "PLESK_DIR=%plesk_dir%"
if "!PLESK_DIR:~-1!"=="\" set "PLESK_DIR=!PLESK_DIR:~0,-1!"
set "MYSQL_BIN=!PLESK_DIR!\MySQL\bin\mysql.exe"

if not exist "!MYSQL_BIN!" (
    echo ERROR: MySQL client not found at: !MYSQL_BIN!
    exit /b 1
)

REM ============================================================================
REM CONFIGURATION
REM ============================================================================

set "MYSQL_USER=admin"
set "MYSQL_PASSWORD=<password_for_mysql>"
set "MYSQL_PORT=8306"

if "!MYSQL_PASSWORD!"=="<password_for_mysql>" (
    echo ERROR: MySQL password has not been configured.
    echo        Open monitor-aspnet.bat and replace ^<password_for_mysql^> with the
    echo        Plesk MySQL admin password, then save the file and run again.
    exit /b 1
)

if not "%~1"=="" (
    set "DOMAIN=%~1"
) else if not defined DOMAIN (
    echo ERROR: Domain name not specified.
    echo Usage: %~nx0 ^<domain^> ^<recipient_email^>
    exit /b 1
)

if not "%~2"=="" (
    set "NOTIFY_EMAIL=%~2"
) else if not defined NOTIFY_EMAIL (
    echo ERROR: Notification email not specified.
    echo Usage: %~nx0 ^<domain^> ^<recipient_email^>
    exit /b 1
)

if not defined SMTP_FROM set "SMTP_FROM=plesk-monitor@!DOMAIN!"

REM ============================================================================
REM SMTP CONFIGURATION
REM Set these to match your external SMTP relay (Tools & Settings > Mail Server
REM Settings > External SMTP). Leave SMTP_AUTH_USER blank for unauthenticated.
REM SMTP_SECURE: leave blank for plain, set to "ssl" for SSL/TLS (port 465),
REM              or "starttls" for STARTTLS (port 587).
REM ============================================================================

if not defined SMTP_SERVER     set "SMTP_SERVER=mail.example.com"
if not defined SMTP_PORT       set "SMTP_PORT=25"
if not defined SMTP_AUTH_USER  set "SMTP_AUTH_USER="
if not defined SMTP_AUTH_PASS  set "SMTP_AUTH_PASS="
if not defined SMTP_SECURE     set "SMTP_SECURE="

echo SMTP server: !SMTP_SERVER!:!SMTP_PORT!

if not defined STATE_DIR set "STATE_DIR=%TEMP%\plesk-monitor"
if not exist "!STATE_DIR!\" (
    mkdir "!STATE_DIR!"
    if !errorlevel! neq 0 (
        echo ERROR: Failed to create state directory: !STATE_DIR!
        exit /b 1
    )
)

REM Sanitize domain name for use as a filename (replace . and - with _)
set "SAFE_DOMAIN=!DOMAIN:.=_!"
set "SAFE_DOMAIN=!SAFE_DOMAIN:-=_!"
set "STATE_FILE=!STATE_DIR!\aspnet_!SAFE_DOMAIN!.state"

echo ============================================================================
echo ASP.NET Monitor ^| Domain: !DOMAIN!
echo ============================================================================
echo Timestamp: %DATE% %TIME%
echo.

REM ============================================================================
REM QUERY ASP.NET STATUS FROM PLESK DATABASE
REM
REM Plesk stores the ASP.NET enabled flag in psa.hosting.asp_dot_net ('true'/'false')
REM linked to psa.domains via dom_id.
REM ============================================================================

echo Querying Plesk database for ASP.NET status of: !DOMAIN!

set "ASPNET_STATUS=unknown"
set "DB_RESULT="
set "MYSQL_ERR_FILE=!STATE_DIR!\aspnet_mysql_err_!RANDOM!.tmp"

"!MYSQL_BIN!" -u%MYSQL_USER% "-p!MYSQL_PASSWORD!" -P%MYSQL_PORT% -N -e "SELECT h.asp_dot_net FROM psa.domains d JOIN psa.hosting h ON d.id = h.dom_id WHERE d.name = '!DOMAIN!'" > "!STATE_DIR!\aspnet_mysql_out.tmp" 2>"!MYSQL_ERR_FILE!"

if !errorlevel! neq 0 (
    echo ERROR: MySQL query failed.
    type "!MYSQL_ERR_FILE!"
    del /q "!MYSQL_ERR_FILE!" "!STATE_DIR!\aspnet_mysql_out.tmp" 2>nul
    exit /b 1
)

for /F "usebackq tokens=*" %%R in ("!STATE_DIR!\aspnet_mysql_out.tmp") do set "DB_RESULT=%%R"
del /q "!MYSQL_ERR_FILE!" "!STATE_DIR!\aspnet_mysql_out.tmp" 2>nul

if not defined DB_RESULT (
    echo ERROR: No result returned from Plesk database.
    echo        Verify the domain exists in Plesk and has web hosting configured.
    exit /b 1
)

echo Database value: [!DB_RESULT!]

if /I "!DB_RESULT!"=="true" set "ASPNET_STATUS=enabled"
if /I "!DB_RESULT!"=="false" set "ASPNET_STATUS=disabled"

if "!ASPNET_STATUS!"=="unknown" (
    echo WARNING: Unexpected database value '!DB_RESULT!' - expected 'true' or 'false'.
    exit /b 1
)

echo Current ASP.NET status:  !ASPNET_STATUS!

REM ============================================================================
REM STATE COMPARISON
REM ============================================================================

set "PREV_STATUS=unknown"
if exist "!STATE_FILE!" (
    set /P PREV_STATUS=<"!STATE_FILE!"
)
echo Previous ASP.NET status: !PREV_STATUS!

REM Persist current state (no trailing space before redirect)
>"!STATE_FILE!" echo !ASPNET_STATUS!
echo.

REM ============================================================================
REM NOTIFICATION LOGIC
REM ============================================================================

if "!ASPNET_STATUS!"=="disabled" (
    if "!PREV_STATUS!"=="disabled" (
        echo INFO: ASP.NET remains disabled. Already alerted - no duplicate notification.
    ) else (
        echo ALERT: ASP.NET has been DISABLED for !DOMAIN! - sending alert...
        set "EMAIL_TYPE=alert"
        call :send_email
        if !errorlevel! neq 0 (
            echo ERROR: Failed to send alert email.
            exit /b 1
        )
        echo Alert sent to: !NOTIFY_EMAIL!
    )
) else (
    if "!PREV_STATUS!"=="disabled" (
        echo INFO: ASP.NET has been RE-ENABLED for !DOMAIN! - sending resolved notification...
        set "EMAIL_TYPE=resolved"
        call :send_email
        if !errorlevel! neq 0 (
            echo ERROR: Failed to send resolved email.
            exit /b 1
        )
        echo Resolved notification sent to: !NOTIFY_EMAIL!
    ) else (
        echo INFO: ASP.NET is enabled. No action required.
    )
)

echo.
echo ============================================================================
echo Monitor check complete.
echo ============================================================================
exit /b 0

REM ============================================================================
REM SUBROUTINE: send_email
REM   Requires EMAIL_TYPE to be set to "alert" or "resolved"
REM   Writes a temporary PowerShell script, executes it, then removes it.
REM ============================================================================
:send_email
set "PS_SCRIPT=!STATE_DIR!\aspnet_email_!RANDOM!.ps1"

if "!EMAIL_TYPE!"=="alert" (
    set "EMAIL_SUBJECT=ALERT: ASP.NET disabled on !DOMAIN! [%COMPUTERNAME%]"
    set "EMAIL_BODY=This is an automated alert from the Plesk ASP.NET monitor.`n`nDomain:    !DOMAIN!`nServer:    %COMPUTERNAME%`nTimestamp: %DATE% %TIME%`n`nMicrosoft ASP.NET has been DISABLED for the above domain in Plesk hosting settings.`n`nPlease log in to Plesk and re-enable ASP.NET for !DOMAIN! if this was not intentional.`n`nThis alert will not repeat until ASP.NET is re-enabled and then disabled again."
) else (
    set "EMAIL_SUBJECT=RESOLVED: ASP.NET re-enabled on !DOMAIN! [%COMPUTERNAME%]"
    set "EMAIL_BODY=This is an automated notification from the Plesk ASP.NET monitor.`n`nDomain:    !DOMAIN!`nServer:    %COMPUTERNAME%`nTimestamp: %DATE% %TIME%`n`nMicrosoft ASP.NET has been RE-ENABLED for the above domain in Plesk hosting settings.`n`nNo further action is required."
)

(
    echo try {
    echo     $params = @{
    echo         SmtpServer  = "!SMTP_SERVER!"
    echo         Port        = !SMTP_PORT!
    echo         From        = "!SMTP_FROM!"
    echo         To          = "!NOTIFY_EMAIL!"
    echo         Subject     = "!EMAIL_SUBJECT!"
    echo         Body        = "!EMAIL_BODY!"
    echo         ErrorAction = 'Stop'
    echo     }
REM Write SSL line only if secure mode is set and not 'none'
if not "!SMTP_SECURE!"=="" if /I not "!SMTP_SECURE!"=="none" (
    echo     $params['UseSsl'] = $true
)
REM Write credential lines only if auth user is configured
if not "!SMTP_AUTH_USER!"=="" (
    echo     $pass = ConvertTo-SecureString '!SMTP_AUTH_PASS!' -AsPlainText -Force
    echo     $params['Credential'] = New-Object System.Management.Automation.PSCredential^('!SMTP_AUTH_USER!', $pass^)
)
    echo     Send-MailMessage @params
    echo     Write-Host 'Email sent successfully.'
    echo } catch {
    echo     Write-Error "Failed to send email: $_"
    echo     exit 1
    echo }
) > "!PS_SCRIPT!"

echo Sending email via !SMTP_SERVER!:!SMTP_PORT! ...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "!PS_SCRIPT!" 2>&1
set "PS_EXIT=!errorlevel!"
del /q "!PS_SCRIPT!" 2>nul
exit /b !PS_EXIT!
