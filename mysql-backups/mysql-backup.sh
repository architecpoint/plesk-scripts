#!/bin/bash
# Purpose: Automated MySQL database backup for Plesk servers with PID locking
# Platform: Linux
# Features:
#   - Prevents concurrent execution using PID file
#   - Backs up all databases except system databases (information_schema, performance_schema, phpmyadmin)
#   - Creates individual SQL dump files per database
#   - Automatically removes orphaned backup files for deleted databases
#   - Proper error handling and detailed logging
#   - Restrictive file permissions for security (600)
#   - Self-update capability with automatic or manual updates
# Usage: ./mysql-backup.sh [--update|--self-update]
# Environment Variables:
#   AUTO_UPDATE - Set to "true" to enable automatic updates (default: false)
#   UPDATE_CHECK_INTERVAL - Hours between update checks (default: 24)
#   GITHUB_BRANCH - GitHub branch to update from (default: main)
# Security: Uses Plesk's built-in 'plesk db' command for authenticated database access

set -euo pipefail

###############################################################################
# SELF-UPDATE FUNCTIONS
###############################################################################

# Self-update configuration
GITHUB_REPO="architecpoint/plesk-scripts"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_RELATIVE_PATH="mysql-backups/mysql-backup.sh"
UPDATE_CHECK_FILE="/tmp/.mysql_backup_update_check"

# Function to log update messages
log_update() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UPDATE] $1"
}

# Function to check if update check is needed based on interval
should_check_for_update() {
    local check_interval_hours="${UPDATE_CHECK_INTERVAL:-24}"
    local check_interval_seconds=$((check_interval_hours * 3600))
    
    if [ ! -f "${UPDATE_CHECK_FILE}" ]; then
        return 0
    fi
    
    local last_check
    last_check=$(stat -c %Y "${UPDATE_CHECK_FILE}" 2>/dev/null || echo 0)
    local current_time
    current_time=$(date +%s)
    local time_diff=$((current_time - last_check))
    
    if [ "${time_diff}" -ge "${check_interval_seconds}" ]; then
        return 0
    fi
    
    return 1
}

# Function to update the check timestamp
update_check_timestamp() {
    touch "${UPDATE_CHECK_FILE}" 2>/dev/null || true
}

# Function to perform self-update
self_update() {
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_update "WARNING: Neither curl nor wget found. Cannot check for updates."
        return 1
    fi
    
    local github_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${SCRIPT_RELATIVE_PATH}"
    local temp_file="${SCRIPT_PATH}.update.$$"
    local backup_file="${SCRIPT_PATH}.backup"
    
    log_update "Checking for updates from GitHub..."
    log_update "Source: ${github_url}"
    
    # Download the latest version
    if command -v curl >/dev/null 2>&1; then
        if ! curl -sSfL "${github_url}" -o "${temp_file}"; then
            log_update "ERROR: Failed to download update from GitHub"
            rm -f "${temp_file}"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "${github_url}" -O "${temp_file}"; then
            log_update "ERROR: Failed to download update from GitHub"
            rm -f "${temp_file}"
            return 1
        fi
    fi
    
    # Verify the downloaded file
    if [ ! -s "${temp_file}" ]; then
        log_update "ERROR: Downloaded file is empty"
        rm -f "${temp_file}"
        return 1
    fi
    
    if ! head -n 1 "${temp_file}" | grep -q "^#!/bin/bash"; then
        log_update "ERROR: Downloaded file does not appear to be a valid bash script"
        rm -f "${temp_file}"
        return 1
    fi
    
    # Compare file contents
    if cmp -s "${SCRIPT_PATH}" "${temp_file}"; then
        log_update "Already running the latest version. No update needed."
        rm -f "${temp_file}"
        update_check_timestamp
        return 0
    fi
    
    log_update "New version available. Installing update..."
    
    # Create backup
    if ! cp -f "${SCRIPT_PATH}" "${backup_file}"; then
        log_update "ERROR: Failed to create backup"
        rm -f "${temp_file}"
        return 1
    fi
    
    # Make executable
    chmod +x "${temp_file}"
    
    # Atomically replace
    if ! mv -f "${temp_file}" "${SCRIPT_PATH}"; then
        log_update "ERROR: Failed to install update"
        mv -f "${backup_file}" "${SCRIPT_PATH}"
        return 1
    fi
    
    log_update "Successfully updated to the latest version!"
    log_update "Backup saved to: ${backup_file}"
    update_check_timestamp
    
    # Re-execute with updated version
    log_update "Restarting with updated version..."
    exec "${SCRIPT_PATH}" "$@"
}

# Check for manual update flag
for arg in "$@"; do
    if [ "${arg}" = "--update" ] || [ "${arg}" = "--self-update" ]; then
        log_update "Manual update requested..."
        self_update "$@"
        exit $?
    fi
done

# Auto-update if enabled
if [ "${AUTO_UPDATE:-false}" = "true" ] && should_check_for_update; then
    log_update "Auto-update enabled. Checking for updates..."
    self_update "$@" || {
        log_update "WARNING: Auto-update failed. Continuing with current version..."
    }
fi

###############################################################################
# MAIN SCRIPT CONFIGURATION
###############################################################################

# Configuration
BACKUP_BASE="/backup/mysql"
FOLDER="${BACKUP_BASE}/data"
PID="${BACKUP_BASE}/mysql.pid"
DB_LIST="${FOLDER}/dbs.txt"
PLESK_BIN="/usr/sbin/plesk"

# Counters for summary
DB_COUNT=0
SUCCESS_COUNT=0
FAILED_COUNT=0
CLEANUP_COUNT=0

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

# Clean up backup files for databases that no longer exist
log_message "Checking for orphaned backup files..."
if [ -d "${FOLDER}" ]; then
    for backup_file in "${FOLDER}"/*.sql; do
        # Skip if no .sql files exist (glob doesn't match anything)
        [ -e "${backup_file}" ] || continue
        
        # Extract database name from filename (remove path and .sql extension)
        db_name=$(basename "${backup_file}" .sql)
        
        # Check if this database still exists in our current database list
        if ! grep -q "^${db_name}$" "${DB_LIST}"; then
            log_message "Removing orphaned backup: ${db_name}.sql (database no longer exists)"
            /bin/rm -f "${backup_file}"
            CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
        fi
    done
    
    if [ "${CLEANUP_COUNT}" -eq 0 ]; then
        log_message "No orphaned backup files found"
    else
        log_message "Cleaned up ${CLEANUP_COUNT} orphaned backup file(s)"
    fi
fi
echo ""

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
log_message "Orphaned backups cleaned: ${CLEANUP_COUNT}"
log_message "Backup location: ${FOLDER}"
log_message "============================================================================"

# Exit with error code if any backups failed
if [ "${FAILED_COUNT}" -gt 0 ]; then
    exit 1
fi

exit 0
