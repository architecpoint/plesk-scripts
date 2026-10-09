#!/bin/bash
# Canonical self-update block. Copy everything from the first banner line down to
# the closing banner into a new script, right after `set -euo pipefail`, and change
# only SCRIPT_RELATIVE_PATH and UPDATE_CHECK_FILE.
#
# Each script keeps its own copy so it stays a single standalone file.
# .github/scripts/check-self-update.sh compares the block from the first banner to the
# end of self_update() against this file (comments, blank lines and the two
# constants are ignored). The flag loop and auto-update tail below are per-script:
# add your own flags inside the loop.
set -euo pipefail

###############################################################################
# SELF-UPDATE FUNCTIONS
###############################################################################

# Self-update configuration
GITHUB_REPO="architecpoint/plesk-scripts"
UPDATE_VERSION="${UPDATE_VERSION:-latest}"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_RELATIVE_PATH="folder-name/script-name.sh"
UPDATE_CHECK_FILE="/tmp/.script_name_update_check"

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

# Function to download a URL to a file using curl or wget
download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -sSfL "${url}" -o "${dest}"
    else
        wget -q "${url}" -O "${dest}"
    fi
}

# Function to resolve the release tag to install: UPDATE_VERSION, or the latest GitHub release
resolve_release_tag() {
    local tag="${UPDATE_VERSION}"

    if [ "${tag}" = "latest" ]; then
        local final_url=""
        if command -v curl >/dev/null 2>&1; then
            final_url=$(curl -sSfL -o /dev/null -w '%{url_effective}' "https://github.com/${GITHUB_REPO}/releases/latest") || return 1
        else
            final_url=$(wget -q --spider -S "https://github.com/${GITHUB_REPO}/releases/latest" 2>&1 | awk '/^ *[Ll]ocation:/ {print $2}' | tail -n 1 | tr -d '\r') || return 1
        fi
        case "${final_url}" in
            */releases/tag/*) tag="${final_url##*/releases/tag/}" ;;
            *) return 1 ;;
        esac
    fi

    # Release tags are dates: vYYYY.MM.DD, with -N for additional releases on the same day
    if ! [[ "${tag}" =~ ^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}(-[0-9]+)?$ ]]; then
        return 1
    fi

    echo "${tag}"
}

# Function to perform self-update
self_update() {
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_update "WARNING: Neither curl nor wget found. Cannot check for updates."
        return 1
    fi

    local release_tag
    local release_url
    local sums_url
    local temp_file="${SCRIPT_PATH}.update.$$"
    local sums_file="${SCRIPT_PATH}.sums.$$"
    local backup_file="${SCRIPT_PATH}.backup"

    if [ -n "${GITHUB_BRANCH:-}" ]; then
        log_update "NOTICE: GITHUB_BRANCH is no longer used. Updates come from GitHub releases; set UPDATE_VERSION to pin a version."
    fi

    if ! release_tag=$(resolve_release_tag); then
        log_update "ERROR: No release to install (none published, or invalid UPDATE_VERSION '${UPDATE_VERSION}'). Keeping current version."
        return 1
    fi
    release_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${release_tag}/${SCRIPT_RELATIVE_PATH}"
    sums_url="https://github.com/${GITHUB_REPO}/releases/download/${release_tag}/SHA256SUMS"

    log_update "Checking for updates from GitHub..."
    log_update "Release: ${release_tag}"
    log_update "Source: ${release_url}"

    # Download the latest version
    if ! download_file "${release_url}" "${temp_file}" || ! download_file "${sums_url}" "${sums_file}"; then
        log_update "ERROR: Failed to download release ${release_tag} from GitHub"
        rm -f "${temp_file}" "${sums_file}"
        return 1
    fi

    # Verify the file against the checksum published with the release
    if ! command -v sha256sum >/dev/null 2>&1; then
        log_update "ERROR: sha256sum not found. Cannot verify the update."
        rm -f "${temp_file}" "${sums_file}"
        return 1
    fi
    local expected_sum
    local actual_sum
    expected_sum=$(awk -v path="${SCRIPT_RELATIVE_PATH}" '$2 == path {print $1}' "${sums_file}")
    actual_sum=$(sha256sum "${temp_file}" | awk '{print $1}')
    rm -f "${sums_file}"
    if [ -z "${expected_sum}" ] || [ "${expected_sum}" != "${actual_sum}" ]; then
        log_update "ERROR: Checksum verification failed for ${SCRIPT_RELATIVE_PATH} (${release_tag}). Keeping current version."
        rm -f "${temp_file}"
        return 1
    fi
    log_update "Checksum verified for ${release_tag}"

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
