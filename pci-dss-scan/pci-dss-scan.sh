#!/bin/bash
set -euo pipefail
# Purpose: Test PCI-DSS compliance issues on a target website - checks for server banner
#          disclosure, insecure cookie attributes, and misconfigured HTTP caching headers.
# Platform: Linux
# Features:
#   - Detects X-Powered-By and Server header disclosure (PCI-DSS banner disclosure)
#   - Checks all cookies for missing Secure and HttpOnly flags
#   - Validates Cache-Control headers for sensitive and non-sensitive pages
#   - Tests multiple paths (homepage, login, checkout, registration, admin)
#   - Colour-coded PASS/FAIL/WARN output with a final summary
#   - Self-update capability with automatic or manual updates
# Usage: ./pci-dss-scan.sh <URL> [--update|--self-update]
#        URL is required (e.g. https://www.example.com)
# Environment Variables:
#   - TARGET_URL:              Override the target domain (required if not passed as argument)
#   - EXTRA_PATHS:             Space-separated list of additional paths to test
#   - AUTO_UPDATE:             Set to "true" to enable automatic updates (default: false)
#   - UPDATE_CHECK_INTERVAL:   Hours between update checks (default: 24)
#   - GITHUB_BRANCH:           GitHub branch to update from (default: main)

###############################################################################
# SELF-UPDATE FUNCTIONS
###############################################################################

GITHUB_REPO="architecpoint/plesk-scripts"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_RELATIVE_PATH="pci-dss-scan/pci-dss-scan.sh"
UPDATE_CHECK_FILE="/tmp/.pci_dss_scan_update_check"

log_update() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UPDATE] $1"
}

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

update_check_timestamp() {
    touch "${UPDATE_CHECK_FILE}" 2>/dev/null || true
}

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
    if cmp -s "${SCRIPT_PATH}" "${temp_file}"; then
        log_update "Already running the latest version. No update needed."
        rm -f "${temp_file}"
        update_check_timestamp
        return 0
    fi
    log_update "New version available. Installing update..."
    if ! cp -f "${SCRIPT_PATH}" "${backup_file}"; then
        log_update "ERROR: Failed to create backup"
        rm -f "${temp_file}"
        return 1
    fi
    chmod +x "${temp_file}"
    if ! mv -f "${temp_file}" "${SCRIPT_PATH}"; then
        log_update "ERROR: Failed to install update"
        mv -f "${backup_file}" "${SCRIPT_PATH}"
        return 1
    fi
    log_update "Successfully updated to the latest version!"
    log_update "Backup saved to: ${backup_file}"
    update_check_timestamp
    log_update "Restarting with updated version..."
    exec "${SCRIPT_PATH}" "$@"
}

for arg in "$@"; do
    if [ "${arg}" = "--update" ] || [ "${arg}" = "--self-update" ]; then
        log_update "Manual update requested..."
        self_update "$@"
        exit $?
    fi
done

if [ "${AUTO_UPDATE:-false}" = "true" ] && should_check_for_update; then
    log_update "Auto-update enabled. Checking for updates..."
    self_update "$@" || {
        log_update "WARNING: Auto-update failed. Continuing with current version..."
    }
fi

###############################################################################
# MAIN SCRIPT CONFIGURATION
###############################################################################

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Target URL - first argument or environment variable (required)
TARGET_URL="${1:-${TARGET_URL:-}}"
# Strip trailing slash
TARGET_URL="${TARGET_URL%/}"

# Remove --update flags if passed as the URL argument
if [[ "${TARGET_URL}" == "--update" || "${TARGET_URL}" == "--self-update" ]]; then
    TARGET_URL=""
fi

if [ -z "${TARGET_URL}" ]; then
    echo "Usage: $0 <URL> [--update|--self-update]"
    echo "       e.g. $0 https://www.example.com"
    echo "       Or set TARGET_URL environment variable."
    exit 1
fi

# Paths to test
DEFAULT_PATHS=(
    "/"
    "/wp-login.php"
    "/wp-admin/"
    "/shop/"
    "/cart/"
    "/checkout/"
    "/my-account/"
)

# Allow extra paths via environment variable
if [ -n "${EXTRA_PATHS:-}" ]; then
    read -ra EXTRA_PATH_ARRAY <<< "${EXTRA_PATHS}"
    ALL_PATHS=("${DEFAULT_PATHS[@]}" "${EXTRA_PATH_ARRAY[@]}")
else
    ALL_PATHS=("${DEFAULT_PATHS[@]}")
fi

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

###############################################################################
# HELPER FUNCTIONS
###############################################################################

pass() {
    echo -e "  ${GREEN}[PASS]${RESET} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "  ${RED}[FAIL]${RESET} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
    echo -e "  ${YELLOW}[WARN]${RESET} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

info() {
    echo -e "  ${CYAN}[INFO]${RESET} $1"
}

section() {
    echo ""
    echo -e "${BOLD}━━━ $1 ━━━${RESET}"
}

# Realistic browser User-Agent to avoid Wordfence / WAF bot-blocking
BROWSER_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

# Fetch response headers (follow redirects, max 10s timeout)
fetch_headers() {
    local url="$1"
    curl -sI \
        --max-time 10 \
        --connect-timeout 5 \
        -L \
        -A "${BROWSER_UA}" \
        "${url}" 2>/dev/null || true
}

# Fetch response headers + body (for cookie inspection in Set-Cookie)
fetch_headers_with_cookies() {
    local url="$1"
    curl -si \
        --max-time 15 \
        --connect-timeout 5 \
        -L \
        -c /dev/null \
        -A "${BROWSER_UA}" \
        "${url}" 2>/dev/null || true
}

###############################################################################
# CHECK 1: SERVER BANNER DISCLOSURE
###############################################################################

check_banner_disclosure() {
    section "CHECK 1: Server Banner Disclosure (PCI DSS Req. 6.5 / 2.2)"
    info "Target: ${TARGET_URL}/"
    echo ""

    local headers
    headers=$(fetch_headers "${TARGET_URL}/")

    # X-Powered-By
    local xpb
    xpb=$(echo "${headers}" | grep -i "^x-powered-by:" || true)
    if [ -n "${xpb}" ]; then
        fail "X-Powered-By header is disclosed: ${xpb}"
        info "Fix: Add 'Header unset X-Powered-By' to Apache config or .htaccess"
        info "     Or in PHP: expose_php = Off in php.ini"
    else
        pass "X-Powered-By header is NOT present"
    fi

    # Server header - check if it discloses version details
    local server_header
    server_header=$(echo "${headers}" | grep -i "^server:" || true)
    if [ -n "${server_header}" ]; then
        # Warn if server version/OS detail is present (e.g., Apache/2.4.51 (Ubuntu))
        if echo "${server_header}" | grep -qiE "([0-9]+\.[0-9]+|ubuntu|debian|centos|fedora|win|microsoft|php)"; then
            fail "Server header discloses version/OS information: ${server_header}"
            info "Fix: Set 'ServerTokens Prod' and 'ServerSignature Off' in Apache config"
        else
            warn "Server header present (minimal disclosure): ${server_header}"
            info "     Consider removing entirely with: Header unset Server"
        fi
    else
        pass "Server header is NOT present or contains no identifying information"
    fi

    # X-AspNet-Version / X-AspNetMvc-Version
    local aspnet
    aspnet=$(echo "${headers}" | grep -iE "^x-aspnet-version:|^x-aspnetmvc-version:" || true)
    if [ -n "${aspnet}" ]; then
        fail "ASP.NET version header disclosed: ${aspnet}"
    else
        pass "No ASP.NET version headers found"
    fi

    # X-Generator (WordPress/Joomla generators)
    local xgen
    xgen=$(echo "${headers}" | grep -i "^x-generator:" || true)
    if [ -n "${xgen}" ]; then
        warn "X-Generator header present: ${xgen}"
        info "     Consider removing this header in WordPress or server config"
    else
        pass "X-Generator header is NOT present"
    fi
}

###############################################################################
# CHECK 2: COOKIE SECURITY ATTRIBUTES
###############################################################################

check_cookie_attributes() {
    section "CHECK 2: Cookie Security Attributes (Secure & HttpOnly flags)"
    echo ""

    local any_cookie_found=false
    local cookie_issues=0

    for path in "${ALL_PATHS[@]}"; do
        local url="${TARGET_URL}${path}"
        local response
        response=$(fetch_headers_with_cookies "${url}")

        # Extract Set-Cookie lines
        local cookies
        cookies=$(echo "${response}" | grep -i "^set-cookie:" || true)

        if [ -z "${cookies}" ]; then
            continue
        fi

        any_cookie_found=true
        info "Cookies found on: ${url}"

        while IFS= read -r cookie_line; do
            local cookie_name
            cookie_name=$(echo "${cookie_line}" | sed 's/^[Ss]et-[Cc]ookie: *//;s/=.*//')

            local missing_flags=()

            # Check HttpOnly
            if ! echo "${cookie_line}" | grep -qi "httponly"; then
                missing_flags+=("HttpOnly")
            fi

            # Check Secure
            if ! echo "${cookie_line}" | grep -qi "; *secure"; then
                missing_flags+=("Secure")
            fi

            # Check SameSite
            if ! echo "${cookie_line}" | grep -qi "samesite"; then
                missing_flags+=("SameSite")
            fi

            if [ ${#missing_flags[@]} -eq 0 ]; then
                pass "Cookie '${cookie_name}' has Secure, HttpOnly, and SameSite flags"
            else
                fail "Cookie '${cookie_name}' is missing: ${missing_flags[*]}"
                info "     Full cookie: ${cookie_line}"
                cookie_issues=$((cookie_issues + 1))
            fi
        done <<< "${cookies}"
    done

    if [ "${any_cookie_found}" = false ]; then
        warn "No Set-Cookie headers detected across tested paths"
        info "     If the site uses session cookies after login, test authenticated paths manually"
    fi

    if [ "${cookie_issues}" -gt 0 ]; then
        echo ""
        info "Fix (WordPress/.htaccess): Add to wp-config.php:"
        info "     define('COOKIE_SECURE', true);"
        info "     define('COOKIEHASH', md5(\$_SERVER['HTTP_HOST']));"
        info "     ini_set('session.cookie_httponly', 1);"
        info "     ini_set('session.cookie_secure', 1);"
        info "     ini_set('session.cookie_samesite', 'Strict');"
        echo ""
        info "Fix (Apache .htaccess - requires mod_headers):"
        info "     Header always edit Set-Cookie (.*) \"\$1; Secure; HttpOnly; SameSite=Strict\""
    fi
}

###############################################################################
# CHECK 3: HTTP CACHING HEADERS
###############################################################################

check_caching_headers() {
    section "CHECK 3: HTTP Caching Headers (Cache-Control)"
    echo ""

    # Sensitive paths that must have strong no-cache directives
    local sensitive_paths=(
        "/wp-login.php"
        "/wp-admin/"
        "/checkout/"
        "/cart/"
        "/my-account/"
    )

    # Non-sensitive paths that should have at least some cache-control
    local public_paths=(
        "/"
        "/shop/"
    )

    echo -e "  ${BOLD}Sensitive pages (must have: no-cache, no-store, private)${RESET}"
    for path in "${sensitive_paths[@]}"; do
        local url="${TARGET_URL}${path}"
        local headers
        headers=$(fetch_headers "${url}")

        local cache_control
        cache_control=$(echo "${headers}" | grep -i "^cache-control:" | head -1 || true)

        local http_status
        http_status=$(echo "${headers}" | grep -i "^HTTP/" | tail -1 | awk '{print $2}' || true)

        # Skip 404s and 403s (page may be behind auth or IP restriction)
        if [[ "${http_status}" == "404" ]]; then
            info "Skipping ${path} (404 Not Found)"
            continue
        fi
        if [[ "${http_status}" == "403" ]]; then
            warn "${path} returned 403 Forbidden — access is restricted"
            info "     Possible causes:"
            info "       1. Wordfence firewall: Wordfence > Firewall > Allowlisted IPs, or temporarily disable"
            info "       2. Plesk ModSecurity: check /var/log/apache2/modsec_audit.log"
            info "       3. .htaccess IP restriction on wp-admin/"
            continue
        fi

        if [ -z "${cache_control}" ]; then
            fail "No Cache-Control header on: ${path}"
        else
            # Check that sensitive pages have all required no-cache directives
            local missing_directives=()
            if ! echo "${cache_control}" | grep -qi "no-store"; then
                missing_directives+=("no-store")
            fi
            if ! echo "${cache_control}" | grep -qi "no-cache"; then
                missing_directives+=("no-cache")
            fi
            if ! echo "${cache_control}" | grep -qi "private"; then
                missing_directives+=("private")
            fi

            if [ ${#missing_directives[@]} -eq 0 ]; then
                pass "${path}: ${cache_control}"
            else
                fail "${path}: missing directives [${missing_directives[*]}] — found: ${cache_control}"
            fi
        fi
    done

    echo ""
    echo -e "  ${BOLD}Public pages (should have: Cache-Control set)${RESET}"
    for path in "${public_paths[@]}"; do
        local url="${TARGET_URL}${path}"
        local headers
        headers=$(fetch_headers "${url}")

        local cache_control
        cache_control=$(echo "${headers}" | grep -i "^cache-control:" | head -1 || true)

        if [ -z "${cache_control}" ]; then
            warn "No Cache-Control header on public page: ${path}"
            info "     Recommended: Cache-Control: no-cache (or a suitable max-age)"
        else
            pass "${path}: ${cache_control}"
        fi
    done

    echo ""
    info "Fix (Apache .htaccess - sensitive pages):"
    info "     <FilesMatch \"\.(php)\$\">"
    info "       Header always set Cache-Control \"max-age=0, must-revalidate, no-cache, no-store, private\""
    info "     </FilesMatch>"
    info ""
    info "     Or for wp-login.php specifically:"
    info "     <Files \"wp-login.php\">"
    info "       Header always set Cache-Control \"max-age=0, must-revalidate, no-cache, no-store, private\""
    info "     </Files>"
}

###############################################################################
# CHECK 4: ADDITIONAL SECURITY HEADERS (BONUS)
###############################################################################

check_additional_headers() {
    section "CHECK 4: Additional Security Headers (Bonus / Best Practice)"
    echo ""

    local headers
    headers=$(fetch_headers "${TARGET_URL}/")

    declare -A RECOMMENDED_HEADERS=(
        ["x-frame-options"]="X-Frame-Options (clickjacking protection)"
        ["x-content-type-options"]="X-Content-Type-Options (MIME sniffing protection)"
        ["strict-transport-security"]="Strict-Transport-Security / HSTS (HTTPS enforcement)"
        ["content-security-policy"]="Content-Security-Policy (XSS / injection protection)"
        ["referrer-policy"]="Referrer-Policy (referrer data control)"
        ["permissions-policy"]="Permissions-Policy (feature policy)"
    )

    for header_name in "${!RECOMMENDED_HEADERS[@]}"; do
        local header_value
        header_value=$(echo "${headers}" | grep -i "^${header_name}:" | head -1 || true)
        if [ -n "${header_value}" ]; then
            pass "${RECOMMENDED_HEADERS[$header_name]}: ${header_value}"
        else
            warn "Missing: ${RECOMMENDED_HEADERS[$header_name]}"
        fi
    done
}

###############################################################################
# SUMMARY
###############################################################################

print_summary() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  SCAN SUMMARY for ${TARGET_URL}${RESET}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  ${GREEN}PASS: ${PASS_COUNT}${RESET}"
    echo -e "  ${RED}FAIL: ${FAIL_COUNT}${RESET}"
    echo -e "  ${YELLOW}WARN: ${WARN_COUNT}${RESET}"
    echo ""
    if [ "${FAIL_COUNT}" -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}All critical PCI-DSS checks passed!${RESET}"
    else
        echo -e "  ${RED}${BOLD}${FAIL_COUNT} critical issue(s) found. Review FAIL items above before re-scanning.${RESET}"
    fi
    echo ""
}

###############################################################################
# ENTRY POINT
###############################################################################

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         PCI-DSS Security Header Compliance Scanner           ║${RESET}"
echo -e "${BOLD}║         $(date '+%Y-%m-%d %H:%M:%S')                                 ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Target: ${CYAN}${TARGET_URL}${RESET}"
echo ""

# Verify curl is available
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required but not installed. Install it with: apt-get install curl"
    exit 1
fi

# Verify target is reachable
info "Testing connectivity to ${TARGET_URL} ..."
if ! curl -sSf --max-time 10 --connect-timeout 5 -o /dev/null -w "" "${TARGET_URL}/" 2>/dev/null; then
    # Try without -f to still proceed even on HTTP errors
    if ! curl -sS --max-time 10 --connect-timeout 5 -o /dev/null "${TARGET_URL}/" 2>/dev/null; then
        echo "ERROR: Cannot reach ${TARGET_URL}. Check the URL and try again."
        exit 1
    fi
fi
pass "Site is reachable"

check_banner_disclosure
check_cookie_attributes
check_caching_headers
check_additional_headers
print_summary
