@echo off
setlocal enabledelayedexpansion
REM Purpose:  Test PCI-DSS compliance issues on a target website - checks for server banner
REM           disclosure, insecure cookie attributes, and misconfigured HTTP caching headers.
REM Platform: Windows
REM Features:
REM   - Detects X-Powered-By and Server header disclosure
REM   - Checks all cookies for missing Secure and HttpOnly flags
REM   - Validates Cache-Control headers for sensitive and public pages
REM   - Tests multiple paths (homepage, login, checkout, registration, admin)
REM   - Colour-coded PASS/FAIL/WARN output with a final summary
REM   - Uses curl.exe (built-in on Windows 10/11) or curl from PATH
REM Usage: pci-dss-scan.bat <URL>
REM        URL is required (e.g. https://www.example.com)
REM Environment Variables:
REM   - TARGET_URL: Override the target domain (required if not passed as argument)

REM ============================================================
REM COLOUR SETUP (via ANSI escape - requires Windows 10+)
REM ============================================================

REM Enable ANSI colours in cmd
reg query "HKCU\Console" /v VirtualTerminalLevel >nul 2>&1 || (
    reg add "HKCU\Console" /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1
)

set "ESC="
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

set "RED=%ESC%[91m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "CYAN=%ESC%[96m"
set "BOLD=%ESC%[1m"
set "RESET=%ESC%[0m"

REM ============================================================
REM CONFIGURATION
REM ============================================================

set PASS_COUNT=0
set FAIL_COUNT=0
set WARN_COUNT=0

REM Target URL from argument or environment variable (required)
if not "%~1"=="" (
    set "TARGET_URL=%~1"
) else if defined TARGET_URL (
    REM use existing env var
) else (
    echo Usage: %~nx0 ^<URL^> [e.g. https://www.example.com]
    echo        Or set TARGET_URL environment variable.
    exit /b 1
)
REM Remove trailing slash
if "!TARGET_URL:~-1!"=="/" set "TARGET_URL=!TARGET_URL:~0,-1!"

REM Locate curl
set "CURL_CMD="
where curl.exe >nul 2>&1 && set "CURL_CMD=curl.exe"
if not defined CURL_CMD (
    where curl >nul 2>&1 && set "CURL_CMD=curl"
)
if not defined CURL_CMD (
    echo ERROR: curl is not available. Install curl or upgrade to Windows 10 1803+.
    exit /b 1
)

REM Temp files
set "TMPDIR=%TEMP%"
set "HDR_FILE=!TMPDIR!\pci_hdr_!RANDOM!.tmp"
set "COOKIE_FILE=!TMPDIR!\pci_cookie_!RANDOM!.tmp"

REM ============================================================
REM HELPER MACROS
REM ============================================================

:run_scan
echo.
echo %BOLD%╔══════════════════════════════════════════════════════════════╗%RESET%
echo %BOLD%║         PCI-DSS Security Header Compliance Scanner           ║%RESET%
echo %BOLD%╚══════════════════════════════════════════════════════════════╝%RESET%
echo.
echo   Target: %CYAN%!TARGET_URL!%RESET%
echo.

REM Verify connectivity
echo   %CYAN%[INFO]%RESET%  Testing connectivity to !TARGET_URL! ...
"!CURL_CMD!" -s --max-time 10 --connect-timeout 5 -o nul -w "%%{http_code}" "!TARGET_URL!/" >nul 2>&1
if errorlevel 1 (
    echo   %RED%[ERROR]%RESET% Cannot reach !TARGET_URL!. Check the URL and try again.
    exit /b 1
)
echo   %GREEN%[PASS]%RESET%  Site is reachable
echo.

call :check_banner_disclosure
call :check_cookie_attributes
call :check_caching_headers
call :check_additional_headers
call :print_summary
goto :cleanup

REM ============================================================
REM CHECK 1: SERVER BANNER DISCLOSURE
REM ============================================================

:check_banner_disclosure
echo.
echo %BOLD%--- CHECK 1: Server Banner Disclosure (PCI DSS Req. 6.5 / 2.2) ---%RESET%
echo.

"!CURL_CMD!" -sI --max-time 10 --connect-timeout 5 -L ^
    -A "Mozilla/5.0 (PCI-DSS Compliance Scanner)" ^
    "!TARGET_URL!/" > "!HDR_FILE!" 2>nul

REM X-Powered-By
findstr /i "X-Powered-By:" "!HDR_FILE!" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=*" %%L in ('findstr /i "X-Powered-By:" "!HDR_FILE!"') do (
        echo   %RED%[FAIL]%RESET%  X-Powered-By header is disclosed: %%L
    )
    echo   %CYAN%[INFO]%RESET%  Fix: Add 'Header unset X-Powered-By' to .htaccess
    echo   %CYAN%[INFO]%RESET%       Or set expose_php = Off in php.ini
    set /a FAIL_COUNT+=1
) else (
    echo   %GREEN%[PASS]%RESET%  X-Powered-By header is NOT present
    set /a PASS_COUNT+=1
)

REM Server header version details
set "SERVER_DETAIL=0"
for /f "tokens=*" %%L in ('findstr /i "^Server:" "!HDR_FILE!" 2^>nul') do (
    echo %%L | findstr /i "[0-9][0-9]*\.[0-9] ubuntu debian centos win microsoft" >nul 2>&1
    if !errorlevel!==0 (
        echo   %RED%[FAIL]%RESET%  Server header discloses version/OS: %%L
        echo   %CYAN%[INFO]%RESET%  Fix: Set ServerTokens Prod and ServerSignature Off in Apache config
        set /a FAIL_COUNT+=1
        set "SERVER_DETAIL=1"
    )
)
if "!SERVER_DETAIL!"=="0" (
    findstr /i "^Server:" "!HDR_FILE!" >nul 2>&1
    if !errorlevel!==0 (
        echo   %YELLOW%[WARN]%RESET%  Server header present but appears minimal
        set /a WARN_COUNT+=1
    ) else (
        echo   %GREEN%[PASS]%RESET%  Server header is NOT present or contains no identifying info
        set /a PASS_COUNT+=1
    )
)

REM X-Generator
findstr /i "X-Generator:" "!HDR_FILE!" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=*" %%L in ('findstr /i "X-Generator:" "!HDR_FILE!"') do (
        echo   %YELLOW%[WARN]%RESET%  X-Generator header present: %%L
    )
    set /a WARN_COUNT+=1
) else (
    echo   %GREEN%[PASS]%RESET%  X-Generator header is NOT present
    set /a PASS_COUNT+=1
)

goto :eof

REM ============================================================
REM CHECK 2: COOKIE SECURITY ATTRIBUTES
REM ============================================================

:check_cookie_attributes
echo.
echo %BOLD%--- CHECK 2: Cookie Security Attributes (Secure and HttpOnly flags) ---%RESET%
echo.

set PATHS=/wp-login.php /checkout/ /cart/ /my-account/

set "ANY_COOKIE_FOUND=0"

for %%P in (!PATHS!) do (
    set "URL=!TARGET_URL!%%P"

    "!CURL_CMD!" -si --max-time 15 --connect-timeout 5 -L ^
        -c nul ^
        -A "Mozilla/5.0 (PCI-DSS Compliance Scanner)" ^
        "!URL!" > "!COOKIE_FILE!" 2>nul

    findstr /i "^Set-Cookie:" "!COOKIE_FILE!" >nul 2>&1
    if !errorlevel!==0 (
        set "ANY_COOKIE_FOUND=1"
        echo   %CYAN%[INFO]%RESET%  Cookies found on: !URL!

        for /f "tokens=*" %%C in ('findstr /i "^Set-Cookie:" "!COOKIE_FILE!"') do (
            set "COOKIE_LINE=%%C"
            set "COOKIE_NAME="
            for /f "tokens=2 delims=: " %%N in ("%%C") do (
                for /f "tokens=1 delims==" %%K in ("%%N") do set "COOKIE_NAME=%%K"
            )

            set "MISSING="

            echo !COOKIE_LINE! | findstr /i "httponly" >nul 2>&1
            if !errorlevel!==1 set "MISSING=!MISSING! HttpOnly"

            echo !COOKIE_LINE! | findstr /i "secure" >nul 2>&1
            if !errorlevel!==1 set "MISSING=!MISSING! Secure"

            echo !COOKIE_LINE! | findstr /i "samesite" >nul 2>&1
            if !errorlevel!==1 set "MISSING=!MISSING! SameSite"

            if "!MISSING!"=="" (
                echo   %GREEN%[PASS]%RESET%  Cookie '!COOKIE_NAME!' has Secure, HttpOnly, and SameSite flags
                set /a PASS_COUNT+=1
            ) else (
                echo   %RED%[FAIL]%RESET%  Cookie '!COOKIE_NAME!' is missing:!MISSING!
                set /a FAIL_COUNT+=1
            )
        )
    )
)

if "!ANY_COOKIE_FOUND!"=="0" (
    echo   %YELLOW%[WARN]%RESET%  No Set-Cookie headers detected across tested paths
    echo   %CYAN%[INFO]%RESET%       Test authenticated pages manually for session cookies
    set /a WARN_COUNT+=1
)

echo.
echo   %CYAN%[INFO]%RESET%  Fix (wp-config.php): define('COOKIE_SECURE', true);
echo   %CYAN%[INFO]%RESET%  Fix (.htaccess):     Header always edit Set-Cookie (.*) "$1; Secure; HttpOnly; SameSite=Strict"

goto :eof

REM ============================================================
REM CHECK 3: HTTP CACHING HEADERS
REM ============================================================

:check_caching_headers
echo.
echo %BOLD%--- CHECK 3: HTTP Caching Headers (Cache-Control) ---%RESET%
echo.

echo   %BOLD%Sensitive pages (must have: no-cache, no-store, private)%RESET%

set SENSITIVE_PATHS=/wp-login.php /wp-admin/ /checkout/ /cart/ /my-account/

for %%P in (!SENSITIVE_PATHS!) do (
    set "URL=!TARGET_URL!%%P"

    "!CURL_CMD!" -sI --max-time 10 --connect-timeout 5 -L ^
        -A "Mozilla/5.0 (PCI-DSS Compliance Scanner)" ^
        "!URL!" > "!HDR_FILE!" 2>nul

    REM Skip 404
    findstr "404" "!HDR_FILE!" | findstr "HTTP" >nul 2>&1
    if !errorlevel!==0 (
        echo   %CYAN%[INFO]%RESET%  Skipping %%P - 404 Not Found
    ) else (
        set "CACHE_LINE="
        for /f "tokens=*" %%L in ('findstr /i "Cache-Control:" "!HDR_FILE!" 2^>nul') do (
            if "!CACHE_LINE!"=="" set "CACHE_LINE=%%L"
        )

        if "!CACHE_LINE!"=="" (
            echo   %RED%[FAIL]%RESET%  No Cache-Control header on: %%P
            set /a FAIL_COUNT+=1
        ) else (
            set "MISSING_CC="
            echo !CACHE_LINE! | findstr /i "no-store" >nul 2>&1
            if !errorlevel!==1 set "MISSING_CC=!MISSING_CC! no-store"
            echo !CACHE_LINE! | findstr /i "no-cache" >nul 2>&1
            if !errorlevel!==1 set "MISSING_CC=!MISSING_CC! no-cache"
            echo !CACHE_LINE! | findstr /i "private" >nul 2>&1
            if !errorlevel!==1 set "MISSING_CC=!MISSING_CC! private"

            if "!MISSING_CC!"=="" (
                echo   %GREEN%[PASS]%RESET%  %%P: !CACHE_LINE!
                set /a PASS_COUNT+=1
            ) else (
                echo   %RED%[FAIL]%RESET%  %%P: missing [!MISSING_CC! ] -- found: !CACHE_LINE!
                set /a FAIL_COUNT+=1
            )
        )
    )
)

echo.
echo   %BOLD%Public pages (should have Cache-Control set)%RESET%

set PUBLIC_PATHS=/ /shop/

for %%P in (!PUBLIC_PATHS!) do (
    set "URL=!TARGET_URL!%%P"

    "!CURL_CMD!" -sI --max-time 10 --connect-timeout 5 -L ^
        -A "Mozilla/5.0 (PCI-DSS Compliance Scanner)" ^
        "!URL!" > "!HDR_FILE!" 2>nul

    set "CACHE_LINE="
    for /f "tokens=*" %%L in ('findstr /i "Cache-Control:" "!HDR_FILE!" 2^>nul') do (
        if "!CACHE_LINE!"=="" set "CACHE_LINE=%%L"
    )

    if "!CACHE_LINE!"=="" (
        echo   %YELLOW%[WARN]%RESET%  No Cache-Control header on public page: %%P
        set /a WARN_COUNT+=1
    ) else (
        echo   %GREEN%[PASS]%RESET%  %%P: !CACHE_LINE!
        set /a PASS_COUNT+=1
    )
)

echo.
echo   %CYAN%[INFO]%RESET%  Fix (.htaccess for sensitive pages):
echo   %CYAN%[INFO]%RESET%       ^<Files "wp-login.php"^>
echo   %CYAN%[INFO]%RESET%         Header always set Cache-Control "max-age=0, must-revalidate, no-cache, no-store, private"
echo   %CYAN%[INFO]%RESET%       ^</Files^>

goto :eof

REM ============================================================
REM CHECK 4: ADDITIONAL SECURITY HEADERS
REM ============================================================

:check_additional_headers
echo.
echo %BOLD%--- CHECK 4: Additional Security Headers (Best Practice) ---%RESET%
echo.

"!CURL_CMD!" -sI --max-time 10 --connect-timeout 5 -L ^
    -A "Mozilla/5.0 (PCI-DSS Compliance Scanner)" ^
    "!TARGET_URL!/" > "!HDR_FILE!" 2>nul

set BONUS_HEADERS=X-Frame-Options X-Content-Type-Options Strict-Transport-Security Content-Security-Policy Referrer-Policy

for %%H in (!BONUS_HEADERS!) do (
    findstr /i "^%%H:" "!HDR_FILE!" >nul 2>&1
    if !errorlevel!==0 (
        for /f "tokens=*" %%L in ('findstr /i "^%%H:" "!HDR_FILE!"') do (
            echo   %GREEN%[PASS]%RESET%  %%L
        )
        set /a PASS_COUNT+=1
    ) else (
        echo   %YELLOW%[WARN]%RESET%  Missing header: %%H
        set /a WARN_COUNT+=1
    )
)

goto :eof

REM ============================================================
REM SUMMARY
REM ============================================================

:print_summary
echo.
echo %BOLD%══════════════════════════════════════════════════════════════%RESET%
echo %BOLD%  SCAN SUMMARY for !TARGET_URL!%RESET%
echo %BOLD%══════════════════════════════════════════════════════════════%RESET%
echo   %GREEN%PASS: !PASS_COUNT!%RESET%
echo   %RED%FAIL: !FAIL_COUNT!%RESET%
echo   %YELLOW%WARN: !WARN_COUNT!%RESET%
echo.
if "!FAIL_COUNT!"=="0" (
    echo   %GREEN%%BOLD%All critical PCI-DSS checks passed!%RESET%
) else (
    echo   %RED%%BOLD%!FAIL_COUNT! critical issue(s) found. Review FAIL items above before re-scanning.%RESET%
)
echo.
goto :eof

REM ============================================================
REM CLEANUP
REM ============================================================

:cleanup
if exist "!HDR_FILE!" del /f /q "!HDR_FILE!" >nul 2>&1
if exist "!COOKIE_FILE!" del /f /q "!COOKIE_FILE!" >nul 2>&1
endlocal
exit /b !FAIL_COUNT!
