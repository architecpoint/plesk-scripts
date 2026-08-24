#!/bin/bash
# Purpose: Automated cleanup of old WordPress backup files in Plesk virtual hosts
# Platform: Linux
# Features:
#   - Scans all WordPress installations in Plesk vhosts for backup files
#   - Removes backups older than specified retention period
#   - Configurable retention via DAYS environment variable (default: 365 days)
#   - Keeps a minimum number of most recent backups per domain regardless of age
#   - Optional email report summarizing backups found/removed per domain
#   - Dry-run mode to preview deletions without removing files
#   - Safe deletion with proper error handling and validation
#   - Detailed logging with timestamps
#   - Exit codes for automation and monitoring
#   - Self-update capability with automatic or manual updates
# Usage: ./remove-wordpress-backups.sh [--dry-run] [--update|--self-update] or DAYS=180 ./remove-wordpress-backups.sh
# Environment Variables:
#   DAYS - Number of days to keep backups (default: 365)
#   MIN_KEEP - Minimum number of most recent backups to keep per domain (default: 3)
#   DRY_RUN - Set to "true" to enable dry-run mode (default: false)
#   EMAIL_TO - Email address to send the per-domain report to (default: unset, no email sent)
#   EMAIL_SUBJECT - Subject line for the email report (default: "WordPress Backup Cleanup Report - <hostname>")
#   SMTP_SERVER - SMTP relay host, used via curl if local 'mail' command is unavailable (default: unset)
#   SMTP_PORT - SMTP relay port (default: 25)
#   SMTP_AUTH_USER - SMTP username, leave unset for unauthenticated relay (default: unset)
#   SMTP_AUTH_PASS - SMTP password (default: unset)
#   SMTP_SECURE - SMTP security: blank/"ssl"/"starttls" (default: blank/plain)
#   SMTP_FROM - Sender address (default: plesk-monitor@<hostname>)
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
MIN_KEEP="${MIN_KEEP:-3}"
BACKUP_PATH="/var/www/vhosts/*/wordpress-backups"
FIND_CMD="/bin/find"
RM_CMD="/bin/rm"
EMAIL_TO="${EMAIL_TO:-}"
EMAIL_SUBJECT="${EMAIL_SUBJECT:-}"
# SMTP fallback for servers without a local MTA (used only if 'mail' command is unavailable)
SMTP_SERVER="${SMTP_SERVER:-}"
SMTP_PORT="${SMTP_PORT:-25}"
SMTP_AUTH_USER="${SMTP_AUTH_USER:-}"
SMTP_AUTH_PASS="${SMTP_AUTH_PASS:-}"
SMTP_SECURE="${SMTP_SECURE:-}"
SMTP_FROM="${SMTP_FROM:-}"

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

    # Validate MIN_KEEP parameter is a non-negative integer
    if ! echo "${MIN_KEEP}" | grep -qE '^[0-9]+$'; then
        log_message "ERROR: MIN_KEEP must be a non-negative integer (provided: ${MIN_KEEP})"
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

    # EMAIL_TO is optional, but if set we need a way to actually send it:
    # either a local MTA via the 'mail' command, or SMTP relay settings for curl.
    if [ -n "${EMAIL_TO}" ] && ! command -v mail >/dev/null 2>&1 && [ -z "${SMTP_SERVER}" ]; then
        log_message "WARNING: EMAIL_TO is set but no 'mail' command or SMTP_SERVER was found. Report will not be emailed."
    fi
    
    return 0
}

# Per-domain scan results, populated by scan_domains(). Parallel arrays indexed by domain.
DOMAIN_NAMES=()
DOMAIN_FOUND=()
DOMAIN_REMOVED_FILES=()  # newline-separated basenames of files removed (or eligible, in dry-run) for that domain
TO_DELETE=()             # full paths of every file eligible for deletion, across all domains

# Function to scan every domain's backup directory: records how many backups
# exist, and which ones are eligible for deletion (older than DAYS, beyond the
# MIN_KEEP newest).
scan_domains() {
    local dir domain total i removed_list
    for dir in ${BACKUP_PATH}; do
        [ -d "${dir}" ] || continue
        domain=$(basename "$(dirname "${dir}")")

        # Newest-first list of backup files in this domain's directory
        local files=()
        while IFS= read -r line; do
            files+=("${line#* }")
        done < <(${FIND_CMD} "${dir}" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn)

        total=${#files[@]}
        removed_list=""

        # Anything beyond the MIN_KEEP newest is eligible if it's also older than DAYS
        if [ "${total}" -gt "${MIN_KEEP}" ]; then
            for ((i = MIN_KEEP; i < total; i++)); do
                if [ -n "$(${FIND_CMD} "${files[$i]}" -mtime +"${DAYS}" 2>/dev/null)" ]; then
                    TO_DELETE+=("${files[$i]}")
                    removed_list+="$(basename "${files[$i]}")"$'\n'
                fi
            done
        fi

        DOMAIN_NAMES+=("${domain}")
        DOMAIN_FOUND+=("${total}")
        DOMAIN_REMOVED_FILES+=("${removed_list}")
    done
}

# Function to build the plain-text per-domain report used both on-screen and in the email
build_report() {
    local action="Removed"
    [ "${DRY_RUN}" = "true" ] && action="Would remove (dry-run)"

    local i domain found removed_files removed_count
    for i in "${!DOMAIN_NAMES[@]}"; do
        domain="${DOMAIN_NAMES[$i]}"
        found="${DOMAIN_FOUND[$i]}"
        removed_files="${DOMAIN_REMOVED_FILES[$i]}"
        removed_count=0
        [ -n "${removed_files}" ] && removed_count=$(printf '%s' "${removed_files}" | grep -c .)

        echo "Domain: ${domain}"
        echo "  Backups found: ${found}"
        echo "  ${action}: ${removed_count}"
        if [ "${removed_count}" -gt 0 ]; then
            printf '%s' "${removed_files}" | sed '/^$/d;s/^/    - /'
        fi
        echo ""
    done
}

# Function to send the report via an SMTP relay using curl, for servers with no local MTA.
# SMTP_SECURE: blank for plain, "ssl" for implicit TLS (typically port 465), "starttls" for
# explicit STARTTLS (typically port 587) — same convention as monitor-aspnet.bat.
send_via_smtp() {
    local subject="$1" body="$2"
    local from="${SMTP_FROM:-plesk-monitor@$(hostname -f 2>/dev/null || hostname)}"
    local scheme="smtp"
    [ "${SMTP_SECURE}" = "ssl" ] && scheme="smtps"

    local msg_file
    msg_file=$(mktemp)
    {
        echo "From: ${from}"
        echo "To: ${EMAIL_TO}"
        echo "Subject: ${subject}"
        echo "Date: $(date -R)"
        echo ""
        echo "${body}"
    } > "${msg_file}"

    local -a curl_args=(--silent --show-error
        --url "${scheme}://${SMTP_SERVER}:${SMTP_PORT}"
        --mail-from "${from}" --mail-rcpt "${EMAIL_TO}"
        --upload-file "${msg_file}")
    [ "${SMTP_SECURE}" = "starttls" ] && curl_args+=(--ssl-reqd)
    [ -n "${SMTP_AUTH_USER}" ] && curl_args+=(--user "${SMTP_AUTH_USER}:${SMTP_AUTH_PASS}")

    local rc=0
    curl "${curl_args[@]}" || rc=$?
    rm -f "${msg_file}"
    return "${rc}"
}

# Function to email the report when EMAIL_TO is configured. Prefers the local
# 'mail' command; falls back to a direct SMTP relay via curl when no local
# MTA is present but SMTP_SERVER is configured.
send_email_report() {
    local body="$1"

    [ -n "${EMAIL_TO}" ] || return 0

    local subject="${EMAIL_SUBJECT:-WordPress Backup Cleanup Report - $(hostname -s 2>/dev/null || hostname)}"

    if command -v mail >/dev/null 2>&1; then
        if echo "${body}" | mail -s "${subject}" "${EMAIL_TO}"; then
            log_message "Report emailed to ${EMAIL_TO}"
            return 0
        fi
        log_message "WARNING: 'mail' command failed to send report to ${EMAIL_TO}"
        return 1
    fi

    if [ -n "${SMTP_SERVER}" ]; then
        if send_via_smtp "${subject}" "${body}"; then
            log_message "Report emailed to ${EMAIL_TO} via SMTP (${SMTP_SERVER}:${SMTP_PORT})"
            return 0
        fi
        log_message "WARNING: Failed to send email report to ${EMAIL_TO} via SMTP (${SMTP_SERVER}:${SMTP_PORT})"
        return 1
    fi

    log_message "WARNING: Cannot send email report - no 'mail' command and no SMTP_SERVER configured."
    return 1
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
    log_message "Minimum backups kept per domain: ${MIN_KEEP}"
    log_message "Search path: ${BACKUP_PATH}"
    echo ""
    
    # Check if any backup directories exist
    # Using ls with redirect to avoid errors if no matches
    if ! ls -d ${BACKUP_PATH} >/dev/null 2>&1; then
        log_message "WARNING: No WordPress backup directories found at ${BACKUP_PATH}"
        log_message "This may be normal if no WordPress installations have backups configured."
        return 0
    fi
    
    log_message "Scanning for backup files older than ${DAYS} days (keeping ${MIN_KEEP} newest per domain)..."

    scan_domains

    local file_count=${#TO_DELETE[@]}
    local report
    report=$(build_report)

    if [ "${file_count}" -eq 0 ]; then
        log_message "No eligible backup files found. Nothing to delete."
        echo ""
        echo "${report}"
        send_email_report "${report}"
        return 0
    fi
    
    log_message "Found ${file_count} backup file(s) to delete."
    echo ""
    echo "${report}"
    
    # In dry-run mode, don't delete - just report what would happen
    if [ "${DRY_RUN}" = "true" ]; then
        log_message "Dry-run complete. ${file_count} file(s) would be deleted."
        log_message "Run without --dry-run flag to actually delete these files."
        send_email_report "${report}"
        return 0
    fi
    
    # Remove old backup files
    if printf '%s\0' "${TO_DELETE[@]}" | xargs -0 "${RM_CMD}" -f; then
        log_message "Successfully removed ${file_count} old backup file(s)."
        send_email_report "${report}"
    else
        log_message "ERROR: Failed to remove some backup files. Check permissions."
        send_email_report "${report}

WARNING: one or more files could not be removed - check server permissions/logs."
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

