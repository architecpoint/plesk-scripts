@echo off
REM ============================================================================
REM MySQL Database Backup Script for Plesk Servers (Windows)
REM 
REM This script backs up all MySQL databases on a Windows Plesk server.
REM 
REM SECURITY WARNING: Replace <password_for_mysql> with your actual MySQL 
REM                   admin password before running this script.
REM
REM Features:
REM - Retrieves list of all databases
REM - Backs up each database to individual SQL dump files
REM - Excludes system databases (information_schema, performance_schema, phpmyadmin)
REM - Uses Plesk MySQL utilities
REM - Proper error handling and logging
REM
REM Usage:
REM   mysql-backup.bat
REM ============================================================================

setlocal enabledelayedexpansion

REM Configuration
set "BACKUP_DIR=%plesk_dir%\Databases\MySQL\backup"
set "DB_LIST=%BACKUP_DIR%\db_list.txt"
set "MYSQL_BIN=%plesk_dir%\MySQL\bin\mysql.exe"
set "MYSQLDUMP_BIN=%plesk_dir%\MySQL\bin\mysqldump.exe"
set "MYSQL_USER=admin"
set "MYSQL_PASSWORD=<password_for_mysql>"
set "MYSQL_PORT=3306"

REM Validate environment
if not defined plesk_dir (
    echo ERROR: plesk_dir environment variable is not set
    echo Please ensure Plesk is properly installed and environment is configured.
    exit /b 1
)

REM Verify MySQL binaries exist
if not exist "%MYSQL_BIN%" (
    echo ERROR: MySQL client not found at: %MYSQL_BIN%
    exit /b 1
)

if not exist "%MYSQLDUMP_BIN%" (
    echo ERROR: mysqldump utility not found at: %MYSQLDUMP_BIN%
    exit /b 1
)

REM Create backup directory if it doesn't exist
if not exist "%BACKUP_DIR%\" (
    echo Creating backup directory: %BACKUP_DIR%
    mkdir "%BACKUP_DIR%"
    if %errorlevel% neq 0 (
        echo ERROR: Failed to create backup directory
        exit /b 1
    )
)

echo ============================================================================
echo MySQL Database Backup - Starting
echo ============================================================================
echo Backup directory: %BACKUP_DIR%
echo.

REM Get list of all databases
echo Retrieving list of databases...
"%MYSQL_BIN%" -u%MYSQL_USER% -p%MYSQL_PASSWORD% -P%MYSQL_PORT% -Ne"SHOW DATABASES" > "%DB_LIST%" 2>&1

if %errorlevel% neq 0 (
    echo ERROR: Failed to retrieve database list. Please check MySQL credentials.
    echo Hint: Replace ^<password_for_mysql^> with your actual MySQL admin password.
    if exist "%DB_LIST%" del /q "%DB_LIST%"
    exit /b 1
)

REM Count databases to backup
set "DB_COUNT=0"
set "SUCCESS_COUNT=0"
set "FAILED_COUNT=0"
set "CLEANUP_COUNT=0"

REM Change to backup directory
cd /d "%BACKUP_DIR%"
if %errorlevel% neq 0 (
    echo ERROR: Failed to change to backup directory
    exit /b 1
)

echo Starting database backup...
echo.

REM Clean up backup files for databases that no longer exist
echo Checking for orphaned backup files...
for %%f in ("%BACKUP_DIR%\*.sql") do (
    set "BACKUP_FILE=%%~nf"
    set "FOUND=0"
    
    REM Check if this database still exists in the database list
    for /F "tokens=1,2* " %%j in (%DB_LIST%) do (
        set "CURRENT_DB=%%j"
        if /i "!BACKUP_FILE!"=="!CURRENT_DB!" set "FOUND=1"
    )
    
    REM If database not found in list, delete the backup file
    if !FOUND! equ 0 (
        if /i not "!BACKUP_FILE!"=="db_list" (
            echo Removing orphaned backup: !BACKUP_FILE!.sql (database no longer exists)
            del /q "%%f"
            set /a CLEANUP_COUNT+=1
        )
    )
)

if %CLEANUP_COUNT% equ 0 (
    echo No orphaned backup files found
) else (
    echo Cleaned up %CLEANUP_COUNT% orphaned backup file(s)
)
echo.

REM Loop through each database and create backup
for /F "tokens=1,2* " %%j in (%DB_LIST%) do (
    set "DB_NAME=%%j"
    
    REM Skip system databases
    if /i "!DB_NAME!"=="information_schema" (
        echo Skipping system database: !DB_NAME!
    ) else if /i "!DB_NAME!"=="performance_schema" (
        echo Skipping system database: !DB_NAME!
    ) else if /i "!DB_NAME!"=="phpmyadmin" (
        echo Skipping system database: !DB_NAME!
    ) else (
        set /a DB_COUNT+=1
        echo [!DB_COUNT!] Backing up database: !DB_NAME!
        
        REM Delete old backup if it exists
        if exist "!DB_NAME!.sql" del /q "!DB_NAME!.sql"
        
        REM Create backup with routines and databases flag
        "%MYSQLDUMP_BIN%" -u%MYSQL_USER% -p%MYSQL_PASSWORD% -P%MYSQL_PORT% --routines --databases !DB_NAME! > "!DB_NAME!.sql" 2>&1
        
        if !errorlevel! neq 0 (
            echo     ERROR: Failed to backup database: !DB_NAME!
            set /a FAILED_COUNT+=1
        ) else (
            echo     Successfully backed up: !DB_NAME!
            set /a SUCCESS_COUNT+=1
        )
    )
)

REM Clean up database list file
if exist "%DB_LIST%" del /q "%DB_LIST%"

echo.
echo ============================================================================
echo MySQL Database Backup - Completed
echo ============================================================================
echo Total databases processed: %DB_COUNT%
echo Successful backups: %SUCCESS_COUNT%
echo Failed backups: %FAILED_COUNT%
echo Orphaned backups cleaned: %CLEANUP_COUNT%
echo Backup location: %BACKUP_DIR%
echo ============================================================================

REM Exit with error code if any backups failed
if %FAILED_COUNT% gtr 0 (
    exit /b 1
)

exit /b 0

