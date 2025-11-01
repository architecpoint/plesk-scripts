#!/bin/bash
# Purpose: Automated cleanup of old WordPress backup files in Plesk virtual hosts
# Platform: Linux
# Features:
#   - Scans all WordPress installations in Plesk vhosts for backup files
#   - Removes backups older than specified retention period
#   - Configurable retention via DAYS environment variable (default: 365 days)
#   - Dry-run mode to preview deletions without removing files
#   - Safe deletion with proper error handling and validation
#   - Detailed logging with timestamps
#   - Exit codes for automation and monitoring
#   - Self-update capability with automatic or manual updates
# Usage: ./remove-wordpress-backups.sh [--dry-run] [--update|--self-update] or DAYS=180 ./remove-wordpress-backups.sh
# Environment Variables:
#   DAYS - Number of days to keep backups (default: 365)
#   DRY_RUN - Set to "true" to enable dry-run mode (default: false)
#   AUTO_UPDATE - Set to "true" to enable automatic updates (default: false)
#   UPDATE_CHECK_INTERVAL - Hours between update checks (default: 24)
#   GITHUB_BRANCH - GitHub branch to update from (default: main)

set -euo pipefail

###############################################################################
# SELF-UPDATE FUNCTIONS
###############################################################################

# Self-update configuration
GITHUB_REPO="architecpoint/plesk-scripts"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_RELATIVE_PATH="remove-old-wordpress-backups/remove-wordpress-backups.sh"
UPDATE_CHECK_FILE="/tmp/.wordpress_backup_cleanup_update_check"

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

# Check for command-line flags
DRY_RUN="${DRY_RUN:-false}"
for arg in "$@"; do
    if [ "${arg}" = "--update" ] || [ "${arg}" = "--self-update" ]; then
        log_update "Manual update requested..."
        self_update "$@"
        exit $?
    elif [ "${arg}" = "--dry-run" ] || [ "${arg}" = "-n" ]; then
        DRY_RUN="true"
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

###
## CONFIGURATION
###
DAYS="${DAYS:-365}"
BACKUP_PATH="/var/www/vhosts/*/wordpress-backups"
FIND_CMD="/bin/find"
RM_CMD="/bin/rm"

###
## FUNCTIONS
###

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to validate configuration
validate_configuration() {
    # Validate DAYS parameter is a positive integer
    if ! echo "${DAYS}" | grep -qE '^[0-9]+$'; then
        log_message "ERROR: DAYS must be a positive integer (provided: ${DAYS})"
        return 1
    fi
    
    # Verify required commands exist
    if [ ! -x "${FIND_CMD}" ]; then
        log_message "ERROR: find command not found at: ${FIND_CMD}"
        return 1
    fi
    
    if [ ! -x "${RM_CMD}" ]; then
        log_message "ERROR: rm command not found at: ${RM_CMD}"
        return 1
    fi
    
    return 0
}

# Function to remove old WordPress backups
remove_wordpress_backups() {
    log_message "============================================================================"
    log_message "WordPress Backup Cleanup - Starting"
    log_message "============================================================================"
    if [ "${DRY_RUN}" = "true" ]; then
        log_message "MODE: DRY-RUN (no files will be deleted)"
    fi
    log_message "Retention period: ${DAYS} days"
    log_message "Search path: ${BACKUP_PATH}"
    echo ""
    
    # Check if any backup directories exist
    # Using ls with redirect to avoid errors if no matches
    if ! ls -d ${BACKUP_PATH} >/dev/null 2>&1; then
        log_message "WARNING: No WordPress backup directories found at ${BACKUP_PATH}"
        log_message "This may be normal if no WordPress installations have backups configured."
        return 0
    fi
    
    log_message "Scanning for backup files older than ${DAYS} days..."
    
    # Count files before deletion
    local file_count
    file_count=$(${FIND_CMD} ${BACKUP_PATH} -type f -mtime +"${DAYS}" 2>/dev/null | wc -l) || file_count=0
    
    if [ "${file_count}" -eq 0 ]; then
        log_message "No backup files older than ${DAYS} days found. Nothing to delete."
        return 0
    fi
    
    log_message "Found ${file_count} backup file(s) to delete."
    
    # In dry-run mode, list files that would be deleted
    if [ "${DRY_RUN}" = "true" ]; then
        echo ""
        log_message "Files that would be deleted (dry-run mode):"
        log_message "------------------------------------------------------------"
        ${FIND_CMD} ${BACKUP_PATH} -type f -mtime +"${DAYS}" -exec ls -lh {} \; 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        echo ""
        log_message "Dry-run complete. ${file_count} file(s) would be deleted."
        log_message "Run without --dry-run flag to actually delete these files."
        return 0
    fi
    
    # Remove old backup files
    if ${FIND_CMD} ${BACKUP_PATH} -type f -mtime +"${DAYS}" -exec ${RM_CMD} -f {} + 2>/dev/null; then
        log_message "Successfully removed ${file_count} old backup file(s)."
    else
        log_message "ERROR: Failed to remove some backup files. Check permissions."
        return 1
    fi
    
    return 0
}

###
## MAIN EXECUTION
###

# Validate configuration
if ! validate_configuration; then
    exit 1
fi

# Execute backup removal
if remove_wordpress_backups; then
    echo ""
    log_message "============================================================================"
    log_message "WordPress Backup Cleanup - Completed Successfully"
    log_message "============================================================================"
    exit 0
else
    echo ""
    log_message "============================================================================"
    log_message "WordPress Backup Cleanup - Completed with Errors"
    log_message "============================================================================"
    exit 1
fi

