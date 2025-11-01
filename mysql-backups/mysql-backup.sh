#!/bin/sh
#
# MySQL Database Backup Script for Plesk Servers (Linux)
# 
# This script backs up all MySQL databases on a Plesk server, excluding system databases.
# It uses a PID file to prevent multiple instances from running simultaneously.
#
# Features:
# - Prevents concurrent execution using PID file
# - Backs up all databases except system databases
# - Creates individual SQL dump files per database
# - Proper error handling and logging
# - Restrictive file permissions for security
#
# Usage:
#   ./mysql-backup.sh
#
# Exit codes:
#   0 - Success
#   1 - Error (database connection failed, backup failed, etc.)
#

set -e

# Configuration
HOME="/backup/mysql"
FOLDER="${HOME}/data"
PID="${HOME}/mysql.pid"
DB_LIST="${FOLDER}/dbs.txt"
PLESK_BIN="/usr/sbin/plesk"

# Counters for summary
DB_COUNT=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# Function to cleanup on exit
cleanup() {
    rm -f "${PID}"
}

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to terminate existing instance
terminate_existing_instance() {
    local existing_pid="$1"
    log_message "Another instance is running (PID: ${existing_pid}). Attempting to terminate..."
    
    if kill -9 "${existing_pid}" 2>/dev/null; then
        log_message "Successfully terminated existing instance"
        sleep 1
    else
        log_message "WARNING: Could not terminate existing instance (may have already exited)"
    fi
}

# Register cleanup function
trap cleanup EXIT INT TERM

# Create backup directory if it doesn't exist
if ! /bin/mkdir -p "${FOLDER}"; then
    log_message "ERROR: Failed to create backup directory: ${FOLDER}"
    exit 1
fi

# Check if another instance is already running
if [ -f "${PID}" ]; then
    KILL=$(cat "${PID}")
    terminate_existing_instance "${KILL}"
    rm -f "${PID}"
fi

# Write current PID to lock file
echo $$ > "${PID}"

# Set restrictive permissions for created files (owner read/write only)
umask 077

log_message "============================================================================"
log_message "MySQL Database Backup - Starting"
log_message "============================================================================"
log_message "Backup directory: ${FOLDER}"
echo ""

# Verify Plesk CLI tool is available
if [ ! -x "${PLESK_BIN}" ]; then
    log_message "ERROR: Plesk CLI tool not found or not executable: ${PLESK_BIN}"
    exit 1
fi

# Get list of databases, excluding system databases
log_message "Retrieving list of databases..."
if ! "${PLESK_BIN}" db -e "SHOW DATABASES" | grep -v -E "^Database|information_schema|performance_schema|phpmyadmin" > "${DB_LIST}"; then
    log_message "ERROR: Cannot connect to MySQL database or retrieve database list"
    exit 1
fi

# Check if any databases were found
if [ ! -s "${DB_LIST}" ]; then
    log_message "WARNING: No databases found to backup"
    rm -f "${DB_LIST}"
    exit 0
fi

log_message "Starting database backup..."
echo ""

# Backup each database
while IFS= read -r database; do
    # Skip empty lines
    [ -z "${database}" ] && continue
    
    DB_COUNT=$((DB_COUNT + 1))
    log_message "[${DB_COUNT}] Backing up database: ${database}"
    
    # Remove old backup file if it exists
    /bin/rm -f "${FOLDER}/${database}.sql"
    
    # Dump database using Plesk's built-in tool
    if "${PLESK_BIN}" db dump "${database}" > "${FOLDER}/${database}.sql" 2>&1; then
        log_message "    Successfully backed up: ${database}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_message "    ERROR: Dump failed for database: ${database}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        # Remove failed backup file
        /bin/rm -f "${FOLDER}/${database}.sql"
    fi
done < "${DB_LIST}"

# Clean up database list file
rm -f "${DB_LIST}"

echo ""
log_message "============================================================================"
log_message "MySQL Database Backup - Completed"
log_message "============================================================================"
log_message "Total databases processed: ${DB_COUNT}"
log_message "Successful backups: ${SUCCESS_COUNT}"
log_message "Failed backups: ${FAILED_COUNT}"
log_message "Backup location: ${FOLDER}"
log_message "============================================================================"

# Exit with error code if any backups failed
if [ "${FAILED_COUNT}" -gt 0 ]; then
    exit 1
fi

exit 0
