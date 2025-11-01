#!/usr/bin/env /bin/bash
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

set -euo pipefail

###
## GLOBAL VARIABLES
###
DAYS=${DAYS:-'365'}
BACKUP_PATH="/var/www/vhosts/*/wordpress-backups"
FIND_CMD="/bin/find"
RM_CMD="/bin/rm"

###
## FUNCTIONS
###

# Function to remove old WordPress backups
remove_wordpress_backups() {
    echo "Starting WordPress backup cleanup..."
    echo "Removing backups older than ${DAYS} days from: ${BACKUP_PATH}"
    
    # Check if any backup directories exist
    if ! ls -d ${BACKUP_PATH} >/dev/null 2>&1; then
        echo "WARNING: No WordPress backup directories found at ${BACKUP_PATH}"
        return 0
    fi
    
    # Count files before deletion
    local file_count
    file_count=$($FIND_CMD ${BACKUP_PATH} -type f -mtime +${DAYS} 2>/dev/null | wc -l) || file_count=0
    
    if [ "${file_count}" -eq 0 ]; then
        echo "No backup files older than ${DAYS} days found. Nothing to delete."
        return 0
    fi
    
    echo "Found ${file_count} backup file(s) to delete."
    
    # Remove old backup files
    $FIND_CMD ${BACKUP_PATH} -type f -mtime +${DAYS} -exec $RM_CMD -f {} + 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Successfully removed ${file_count} old backup file(s)."
    else
        echo "ERROR: Failed to remove some backup files. Check permissions."
        return 1
    fi
}

###
## MAIN EXECUTION
###

# Validate DAYS parameter
if ! [[ "${DAYS}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: DAYS must be a positive integer (provided: ${DAYS})"
    exit 1
fi

# Execute backup removal
remove_wordpress_backups

echo "WordPress backup cleanup completed successfully."
exit 0

