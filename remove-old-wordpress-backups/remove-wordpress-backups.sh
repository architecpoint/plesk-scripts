#!/bin/sh
#
# WordPress Backup Cleanup Script for Plesk Servers
#
# This script removes old WordPress backup files from all Plesk virtual hosts
# to free up disk space. It searches for backup files older than a specified
# number of days and deletes them safely.
#
# Usage:
#   ./remove-wordpress-backups.sh
#   DAYS=180 ./remove-wordpress-backups.sh  # Custom retention period
#
# Environment Variables:
#   DAYS - Number of days to keep backups (default: 365)
#
# Exit codes:
#   0 - Success
#   1 - Error (invalid parameters, permission issues, etc.)
#

set -euo pipefail

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
    file_count=$(${FIND_CMD} ${BACKUP_PATH} -type f -mtime +${DAYS} 2>/dev/null | wc -l) || file_count=0
    
    if [ "${file_count}" -eq 0 ]; then
        log_message "No backup files older than ${DAYS} days found. Nothing to delete."
        return 0
    fi
    
    log_message "Found ${file_count} backup file(s) to delete."
    
    # Remove old backup files
    if ${FIND_CMD} ${BACKUP_PATH} -type f -mtime +${DAYS} -exec ${RM_CMD} -f {} + 2>/dev/null; then
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

