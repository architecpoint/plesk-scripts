@echo off
REM ============================================================================
REM MySQL Database Backup Script for Plesk Servers (Windows)
REM 
REM This script backs up all MySQL databases on a Windows Plesk server.
REM 
REM IMPORTANT: Replace <password_for_mysql> with your actual MySQL admin 
REM            password before running this script.
REM
REM Features:
REM - Retrieves list of all databases
REM - Backs up each database to individual SQL dump files
REM - Uses Plesk MySQL utilities
REM ============================================================================

REM Check if plesk_dir environment variable is set
if not defined plesk_dir (
    echo ERROR: plesk_dir environment variable is not set
    exit /b 1
)

REM Create backup directory if it doesn't exist
if not exist "%plesk_dir%\Databases\MySQL\backup\" (
    mkdir "%plesk_dir%\Databases\MySQL\backup\"
)

REM Get list of all databases
echo Retrieving list of databases...
"%plesk_dir%\MySQL\bin\mysql.exe" -uadmin -p<password_for_mysql> -P3306 -Ne"SHOW DATABASES" > "%plesk_dir%\Databases\MySQL\backup\db_list.txt"

if %errorlevel% neq 0 (
    echo ERROR: Failed to retrieve database list. Please check MySQL credentials.
    exit /b 1
)

REM Change to backup directory
cd /d "%plesk_dir%\Databases\MySQL\backup"

echo Starting database backup...

REM Loop through each database and create backup
for /F "tokens=1,2* " %%j in (db_list.txt) do (
    echo Backing up database: %%j
    "%plesk_dir%\MySQL\bin\mysqldump.exe" -uadmin -p<password_for_mysql> -P3306 --routines --databases %%j > "%plesk_dir%\Databases\MySQL\backup\%%j.sql"
    
    if %errorlevel% neq 0 (
        echo ERROR: Failed to backup database: %%j
    ) else (
        echo Successfully backed up: %%j
    )
)

echo Database backup completed successfully
exit /b 0

