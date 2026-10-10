#!/bin/bash
# Purpose: Detect sustained CPU load on a Plesk server, attribute it to subscriptions, and email an alert
#          unless the load is caused by an attack that fail2ban is already banning
# Platform: Linux (AlmaLinux with Plesk Obsidian)
# Features:
#   - Samples the 1-minute load each run and alerts only on sustained load (default: 80% of samples
#     above 1.0 x CPU cores across a 30-minute window), never on a brief spike
#   - Attributes CPU to Plesk subscriptions via the owning system user (top processes, per subscription)
#   - Analyzes the access logs of the busiest subscriptions to find offenders: IPs banned by fail2ban
#     plus IPs matching bot-scan heuristics (request rate, 404/403 ratio, probe paths)
#   - Suppresses the alert when banned offenders account for most of the attack traffic (fail2ban is
#     handling it), and escalates with a lower-urgency notice if load is still high a full window later
#   - Labels the likely cause: attack-like traffic, web application, database or other process
#   - ALERT on entering an incident, periodic REMINDER, RESOLVED on recovery, with an alert cooldown
#   - Incident log for later review; read-only, never bans or changes anything
#   - PID locking prevents concurrent runs
#   - Self-update capability with automatic or manual updates
# Usage: ./monitor-cpu-load.sh [--report] [--update|--self-update]
#        Run as root every 5 minutes from root's crontab or a Plesk Scheduled Task:
#        */5 * * * * /root/monitor-cpu-load.sh >/dev/null 2>&1
#        --report prints the analysis as HTML to stdout now, ignoring the load window; no email, no state change
# Requirements: root, curl or the 'mail' command (for email), 'plesk' CLI, optional fail2ban-client
# Environment Variables:
#   EMAIL_TO - Address that receives alerts (default: unset, log only)
#   LOAD_THRESHOLD_FACTOR - Load threshold as a multiple of CPU cores (default: 1.0)
#   WINDOW_MINUTES - Length of the sustained-load window (default: 30)
#   SAMPLE_INTERVAL_MINUTES - How often cron runs this script (default: 5)
#   SUSTAINED_PERCENT - Percent of samples in the window that must exceed the threshold (default: 80)
#   HANDLED_PERCENT - Percent of attack traffic from banned IPs at which fail2ban is considered to be handling it (default: 80)
#   ATTACK_SHARE_PERCENT - Percent of analyzed web requests that must come from offenders to call the load attack-like (default: 50)
#   ANALYSIS_MINUTES - Minutes of access log to analyze (default: 30)
#   MAX_LOG_LINES - Most recent lines read from each access log (default: 500000)
#   TOP_SUBSCRIPTIONS - Number of busiest subscriptions whose logs are analyzed (default: 3)
#   OFFENDER_RPM - Requests per minute from one IP above which it is an offender (default: 30)
#   OFFENDER_BAD_MIN - Minimum 401/403/404 responses (with a 50% ratio) to one IP to be an offender (default: 50)
#   OFFENDER_PROBE_MIN - Minimum probe-path hits from one IP to be an offender (default: 20)
#   PROBE_PATTERN - Extended regex of probe paths (default: wp-login.php, xmlrpc.php, .env, .git, phpmyadmin, vendor, .aws, eval-stdin)
#   F2B_EXCLUDE_JAILS - Space-separated fail2ban jails ignored for banned IPs (default: "ssh sshd")
#   ALERT_COOLDOWN_MINUTES - Minimum minutes between alerts for new incidents (default: 60)
#   REMINDER_HOURS - Hours between reminders during a long incident (default: 6)
#   LOG_ROOT - Plesk per-domain log root (default: /var/www/vhosts/system)
#   STATE_DIR - Samples and incident state (default: /var/lib/plesk-cpu-monitor)
#   LOG_FILE - Incident log (default: /var/log/plesk-cpu-monitor.log)
#   SMTP_SERVER - SMTP relay host, used via curl, takes priority over 'mail' (default: unset)
#   SMTP_PORT - SMTP relay port (default: 25)
#   SMTP_AUTH_USER - SMTP username, leave unset for unauthenticated relay (default: unset)
#   SMTP_AUTH_PASS - SMTP password (default: unset)
#   SMTP_SECURE - SMTP security: blank/"ssl"/"starttls" (default: blank/plain)
#   SMTP_FROM - Sender address (default: plesk-monitor@<hostname>)
#   AUTO_UPDATE - Set to "true" to enable automatic updates (default: false)
#   UPDATE_CHECK_INTERVAL - Hours between update checks (default: 24)
#   UPDATE_VERSION - Release tag to install on update, e.g. v2026.05.01 (default: latest release)
# Security: Reads other users' processes and logs, so it must run as root. SMTP_AUTH_PASS is read from the
#           environment; never commit real credentials. State files are created with umask 077.

set -euo pipefail

###############################################################################
# SELF-UPDATE FUNCTIONS
###############################################################################

# Self-update configuration
GITHUB_REPO="architecpoint/plesk-scripts"
UPDATE_VERSION="${UPDATE_VERSION:-latest}"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_RELATIVE_PATH="monitor-cpu-load/monitor-cpu-load.sh"
UPDATE_CHECK_FILE="/tmp/.plesk_cpu_monitor_update_check"

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
REPORT_ONLY="false"
for arg in "$@"; do
    if [ "${arg}" = "--update" ] || [ "${arg}" = "--self-update" ]; then
        log_update "Manual update requested..."
        self_update "$@"
        exit $?
    elif [ "${arg}" = "--report" ]; then
        REPORT_ONLY="true"
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

# Cron's default PATH lacks /usr/sbin and /usr/local/sbin, where plesk and fail2ban-client live
PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin"
export PATH

EMAIL_TO="${EMAIL_TO:-}"
LOAD_THRESHOLD_FACTOR="${LOAD_THRESHOLD_FACTOR:-1.0}"
WINDOW_MINUTES="${WINDOW_MINUTES:-30}"
SAMPLE_INTERVAL_MINUTES="${SAMPLE_INTERVAL_MINUTES:-5}"
SUSTAINED_PERCENT="${SUSTAINED_PERCENT:-80}"
HANDLED_PERCENT="${HANDLED_PERCENT:-80}"
ATTACK_SHARE_PERCENT="${ATTACK_SHARE_PERCENT:-50}"
ANALYSIS_MINUTES="${ANALYSIS_MINUTES:-30}"
MAX_LOG_LINES="${MAX_LOG_LINES:-500000}"
TOP_SUBSCRIPTIONS="${TOP_SUBSCRIPTIONS:-3}"
OFFENDER_RPM="${OFFENDER_RPM:-30}"
OFFENDER_BAD_MIN="${OFFENDER_BAD_MIN:-50}"
OFFENDER_PROBE_MIN="${OFFENDER_PROBE_MIN:-20}"
export PROBE_PATTERN="${PROBE_PATTERN:-wp-login\.php|xmlrpc\.php|/\.env|/\.git|phpmyadmin|/vendor/|/\.aws|eval-stdin}"
F2B_EXCLUDE_JAILS="${F2B_EXCLUDE_JAILS:-ssh sshd}"
ALERT_COOLDOWN_MINUTES="${ALERT_COOLDOWN_MINUTES:-60}"
REMINDER_HOURS="${REMINDER_HOURS:-6}"
LOG_ROOT="${LOG_ROOT:-/var/www/vhosts/system}"
STATE_DIR="${STATE_DIR:-/var/lib/plesk-cpu-monitor}"
LOG_FILE="${LOG_FILE:-/var/log/plesk-cpu-monitor.log}"
SMTP_SERVER="${SMTP_SERVER:-}"
SMTP_PORT="${SMTP_PORT:-25}"
SMTP_AUTH_USER="${SMTP_AUTH_USER:-}"
SMTP_AUTH_PASS="${SMTP_AUTH_PASS:-}"
SMTP_SECURE="${SMTP_SECURE:-}"
SMTP_FROM="${SMTP_FROM:-}"

SAMPLES_FILE="${STATE_DIR}/samples"
STATE_FILE="${STATE_DIR}/state"
PIDFILE="${STATE_DIR}/monitor.pid"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
WORK=""
F2B_WARNING=""

###############################################################################
# FUNCTIONS
###############################################################################

log_message() {
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "${line}" >> "${LOG_FILE}" 2>/dev/null || true
    if [ -t 1 ]; then
        echo "${line}"
    fi
}

cleanup() {
    rm -f "${PIDFILE}"
    if [ -n "${WORK}" ]; then
        rm -rf "${WORK}"
    fi
}

validate_configuration() {
    if [ "${EUID}" -ne 0 ]; then
        echo "ERROR: This script must run as root (needs process, log and fail2ban access)" >&2
        exit 1
    fi

    if ! [[ "${LOAD_THRESHOLD_FACTOR}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "ERROR: LOAD_THRESHOLD_FACTOR must be a number (provided: ${LOAD_THRESHOLD_FACTOR})" >&2
        exit 1
    fi

    local var
    for var in WINDOW_MINUTES SAMPLE_INTERVAL_MINUTES SUSTAINED_PERCENT HANDLED_PERCENT ATTACK_SHARE_PERCENT \
        ANALYSIS_MINUTES MAX_LOG_LINES TOP_SUBSCRIPTIONS OFFENDER_RPM OFFENDER_BAD_MIN OFFENDER_PROBE_MIN \
        ALERT_COOLDOWN_MINUTES REMINDER_HOURS; do
        if ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
            echo "ERROR: ${var} must be a positive integer (provided: ${!var})" >&2
            exit 1
        fi
    done
    if [ "${WINDOW_MINUTES}" -le "${SAMPLE_INTERVAL_MINUTES}" ]; then
        echo "ERROR: WINDOW_MINUTES must be larger than SAMPLE_INTERVAL_MINUTES" >&2
        exit 1
    fi
}

acquire_lock() {
    if [ -f "${PIDFILE}" ]; then
        local old_pid
        old_pid=$(cat "${PIDFILE}" 2>/dev/null || true)
        if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
            log_message "Another run is active (PID: ${old_pid}), exiting"
            exit 0
        fi
    fi
    echo $$ > "${PIDFILE}"
    trap cleanup EXIT
}

compute_threshold() {
    CORES=$(nproc)
    THRESHOLD=$(awk -v f="${LOAD_THRESHOLD_FACTOR}" -v c="${CORES}" 'BEGIN { printf "%.2f", f * c }')
}

# Appends the current 1-minute load and drops samples older than the window plus one interval.
# The extra interval keeps a sample at the window's start so full coverage can be proven.
record_sample() {
    local now cutoff
    now=$(date +%s)
    echo "${now} $(cut -d' ' -f1 /proc/loadavg)" >> "${SAMPLES_FILE}"
    cutoff=$((now - (WINDOW_MINUTES + SAMPLE_INTERVAL_MINUTES) * 60))
    awk -v c="${cutoff}" '$1 >= c' "${SAMPLES_FILE}" > "${SAMPLES_FILE}.tmp"
    mv -f "${SAMPLES_FILE}.tmp" "${SAMPLES_FILE}"
}

# Sets CORES, THRESHOLD, LOAD_NOW, SAMPLE_TOTAL, SAMPLE_OVER, SAMPLE_PCT, WINDOW_COVERED, SUSTAINED
evaluate_load() {
    local now window_start oldest
    now=$(date +%s)
    window_start=$((now - WINDOW_MINUTES * 60))
    compute_threshold
    LOAD_NOW=$(tail -n 1 "${SAMPLES_FILE}" | cut -d' ' -f2)
    oldest=$(head -n 1 "${SAMPLES_FILE}" | cut -d' ' -f1)

    read -r SAMPLE_TOTAL SAMPLE_OVER < <(awk -v t="${THRESHOLD}" -v w="${window_start}" \
        '$1 >= w { n++; if ($2 > t) v++ } END { printf "%d %d\n", n, v }' "${SAMPLES_FILE}")
    SAMPLE_PCT=0
    if [ "${SAMPLE_TOTAL}" -gt 0 ]; then
        SAMPLE_PCT=$((SAMPLE_OVER * 100 / SAMPLE_TOTAL))
    fi

    WINDOW_COVERED="false"
    if [ "${oldest}" -le "${window_start}" ]; then
        WINDOW_COVERED="true"
    fi

    SUSTAINED="false"
    if [ "${WINDOW_COVERED}" = "true" ] && [ "${SAMPLE_PCT}" -ge "${SUSTAINED_PERCENT}" ]; then
        SUSTAINED="true"
    fi
}

# State file holds only whitelisted keys; values are validated before use
load_state() {
    STATE="normal"
    MITIGATED_SINCE=0
    INCIDENT_START=0
    LAST_ALERT_TS=0
    LAST_REMINDER_TS=0
    ALERT_SENT="false"
    [ -f "${STATE_FILE}" ] || return 0

    local key value
    while IFS='=' read -r key value; do
        case "${key}" in
            STATE)
                case "${value}" in
                    normal|mitigated|incident) STATE="${value}" ;;
                esac
                ;;
            ALERT_SENT)
                if [ "${value}" = "true" ]; then
                    ALERT_SENT="true"
                fi
                ;;
            MITIGATED_SINCE|INCIDENT_START|LAST_ALERT_TS|LAST_REMINDER_TS)
                if [[ "${value}" =~ ^[0-9]+$ ]]; then
                    printf -v "${key}" '%s' "${value}"
                fi
                ;;
        esac
    done < "${STATE_FILE}"
    return 0
}

save_state() {
    {
        echo "STATE=${STATE}"
        echo "MITIGATED_SINCE=${MITIGATED_SINCE}"
        echo "INCIDENT_START=${INCIDENT_START}"
        echo "LAST_ALERT_TS=${LAST_ALERT_TS}"
        echo "LAST_REMINDER_TS=${LAST_REMINDER_TS}"
        echo "ALERT_SENT=${ALERT_SENT}"
    } > "${STATE_FILE}.tmp"
    mv -f "${STATE_FILE}.tmp" "${STATE_FILE}"
}

# Writes ${WORK}/proc_comm_cpu ("command cpu") and ${WORK}/sub_cpu ("subscription-or-user cpu mapped"),
# both sorted by CPU descending, plus ${WORK}/top_subs. CPU is percent of one core.
collect_cpu() {
    LC_ALL=C top -b -n 2 -d 2 -w 512 \
        | awk '/^ *PID +USER/ { i++; next } i == 2 && $1 ~ /^[0-9]+$/ { print $1, $9 }' > "${WORK}/pcpu"
    ps -eo pid=,user:32=,comm= > "${WORK}/procs"

    awk 'FNR == NR { cpu[$1] = $2; next } ($1 in cpu) { u[$2] += cpu[$1] } END { for (k in u) printf "%s %.1f\n", k, u[k] }' \
        "${WORK}/pcpu" "${WORK}/procs" | sort -k2,2nr > "${WORK}/proc_user_cpu"
    awk 'FNR == NR { cpu[$1] = $2; next } ($1 in cpu) { c[$3] += cpu[$1] } END { for (k in c) printf "%s %.1f\n", k, c[k] }' \
        "${WORK}/pcpu" "${WORK}/procs" | sort -k2,2nr > "${WORK}/proc_comm_cpu"

    : > "${WORK}/login2sub"
    : > "${WORK}/dom2sub"
    if command -v plesk >/dev/null 2>&1; then
        plesk db -Ne "SELECT su.login, w.name FROM hosting h JOIN sys_users su ON su.id = h.sys_user_id JOIN domains w ON w.id = h.dom_id WHERE w.webspace_id = 0" \
            > "${WORK}/login2sub" 2>/dev/null || log_message "WARNING: Could not read subscription owners from the Plesk database"
        plesk db -Ne "SELECT d.name, w.name FROM domains d JOIN domains w ON w.id = IF(d.webspace_id = 0, d.id, d.webspace_id)" \
            > "${WORK}/dom2sub" 2>/dev/null || log_message "WARNING: Could not read domains from the Plesk database"
    else
        log_message "WARNING: plesk CLI not found, CPU cannot be attributed to subscriptions"
    fi

    awk -F'\t' 'FILENAME == ARGV[1] { owner[$1] = $2; next }
        { split($0, f, " "); name = (f[1] in owner) ? owner[f[1]] : f[1]; cpu[name] += f[2]; mapped[name] = (f[1] in owner) }
        END { for (k in cpu) printf "%s %.1f %d\n", k, cpu[k], mapped[k] }' \
        "${WORK}/login2sub" "${WORK}/proc_user_cpu" | sort -k2,2nr > "${WORK}/sub_cpu"
    awk '$3 == 1 && $2 > 0 { print $1 }' "${WORK}/sub_cpu" | head -n "${TOP_SUBSCRIPTIONS}" > "${WORK}/top_subs"
}

# Writes ${WORK}/banned_raw as "ip jail" lines for every jail except the excluded ones. Sets F2B_WARNING.
collect_banned() {
    F2B_WARNING=""
    : > "${WORK}/banned_raw"
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        F2B_WARNING="fail2ban-client is not installed; banned IPs could not be checked"
        return 0
    fi

    local status jail
    if ! status=$(fail2ban-client status 2>/dev/null); then
        F2B_WARNING="fail2ban is not responding; banned IPs could not be checked"
        return 0
    fi

    for jail in $(printf '%s\n' "${status}" | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' '); do
        case " ${F2B_EXCLUDE_JAILS} " in
            *" ${jail} "*) continue ;;
        esac
        fail2ban-client status "${jail}" 2>/dev/null \
            | sed -n 's/.*Banned IP list:[[:space:]]*//p' | tr ' ' '\n' \
            | awk -v j="${jail}" 'NF { print $1, j }' >> "${WORK}/banned_raw" || true
    done
    return 0
}

recent_minutes() {
    local i list=""
    for ((i = 0; i < ANALYSIS_MINUTES; i++)); do
        list+="$(LC_ALL=C date -d "-${i} min" '+%d/%b/%Y:%H:%M'),"
    done
    echo "${list%,}"
}

# Reads each top subscription's access logs for the analysis window into ${WORK}/all.tsv
# ("subscription ip requests bad probe") and ${WORK}/sub_requests ("subscription requests").
analyze_logs() {
    local minutes sub dom main log
    minutes=$(recent_minutes)
    : > "${WORK}/all.tsv"
    : > "${WORK}/sub_requests"

    while read -r sub; do
        [ -n "${sub}" ] || continue
        {
            while IFS=$'\t' read -r dom main; do
                [ "${main}" = "${sub}" ] || continue
                for log in "${LOG_ROOT}/${dom}/logs/access_log" "${LOG_ROOT}/${dom}/logs/access_ssl_log"; do
                    if [ -r "${log}" ]; then
                        tail -n "${MAX_LOG_LINES}" "${log}"
                    fi
                done
            done < "${WORK}/dom2sub"
            true
        } | MINUTES="${minutes}" awk '
            BEGIN { n = split(ENVIRON["MINUTES"], m, ","); for (i = 1; i <= n; i++) want[m[i]] = 1; probe = ENVIRON["PROBE_PATTERN"] }
            { t = substr($4, 2, 17); if (!(t in want)) next
              ip = $1; req[ip]++
              if ($9 == 401 || $9 == 403 || $9 == 404) bad[ip]++
              if ($7 ~ probe) hit[ip]++ }
            END { for (ip in req) printf "%s\t%d\t%d\t%d\n", ip, req[ip], bad[ip] + 0, hit[ip] + 0 }' > "${WORK}/ips.tsv"
        awk -F'\t' -v s="${sub}" '{ t += $2 } END { printf "%s\t%d\n", s, t + 0 }' "${WORK}/ips.tsv" >> "${WORK}/sub_requests"
        awk -F'\t' -v s="${sub}" '{ print s "\t" $0 }' "${WORK}/ips.tsv" >> "${WORK}/all.tsv"
    done < "${WORK}/top_subs"
    return 0
}

# Sets WEB_TOTAL, ATTACK_TOTAL, BANNED_TOTAL, ATTACK_SHARE, HANDLED_PCT, CAUSE, HANDLED and writes
# ${WORK}/offenders ("ip requests bad probe jails"), busiest first.
analyze_offenders() {
    {
        printf -- '-\t-\n'
        awk '{ a[$1] = ($1 in a) ? a[$1] "," $2 : $2 } END { for (ip in a) printf "%s\t%s\n", ip, a[ip] }' "${WORK}/banned_raw"
    } > "${WORK}/banned.tsv"

    awk -F'\t' -v mins="${ANALYSIS_MINUTES}" -v rpm="${OFFENDER_RPM}" -v badmin="${OFFENDER_BAD_MIN}" \
        -v hitmin="${OFFENDER_PROBE_MIN}" -v tot="${WORK}/web_total" '
        FNR == NR { jails[$1] = $2; next }
        { req[$2] += $3; bad[$2] += $4; hit[$2] += $5; total += $3 }
        END {
            for (ip in req) {
                banned = (ip in jails)
                heuristic = (req[ip] / mins >= rpm) || (bad[ip] >= badmin && bad[ip] / req[ip] >= 0.5) || (hit[ip] >= hitmin)
                if (banned || heuristic) printf "%s\t%d\t%d\t%d\t%s\n", ip, req[ip], bad[ip], hit[ip], banned ? jails[ip] : "-"
            }
            printf "%d\n", total + 0 > tot
        }' "${WORK}/banned.tsv" "${WORK}/all.tsv" | sort -t$'\t' -k2,2nr > "${WORK}/offenders"

    WEB_TOTAL=$(cat "${WORK}/web_total")
    ATTACK_TOTAL=$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "${WORK}/offenders")
    BANNED_TOTAL=$(awk -F'\t' '$5 != "-" { s += $2 } END { print s + 0 }' "${WORK}/offenders")
    ATTACK_SHARE=0
    HANDLED_PCT=0
    if [ "${WEB_TOTAL}" -gt 0 ]; then
        ATTACK_SHARE=$((ATTACK_TOTAL * 100 / WEB_TOTAL))
    fi
    if [ "${ATTACK_TOTAL}" -gt 0 ]; then
        HANDLED_PCT=$((BANNED_TOTAL * 100 / ATTACK_TOTAL))
    fi

    local top_comm
    top_comm=$(head -n 1 "${WORK}/proc_comm_cpu" | cut -d' ' -f1)
    HANDLED="false"
    if [ "${WEB_TOTAL}" -gt 0 ] && [ "${ATTACK_SHARE}" -ge "${ATTACK_SHARE_PERCENT}" ]; then
        CAUSE="Attack-like traffic (${ATTACK_SHARE}% of requests from offenders)"
        if [ "${HANDLED_PCT}" -ge "${HANDLED_PERCENT}" ]; then
            HANDLED="true"
        fi
    else
        case "${top_comm}" in
            php*|lsphp*|httpd*|nginx*|apache*) CAUSE="Web application load; the traffic does not look like an attack" ;;
            mysqld*|mariadbd*|mariadb*) CAUSE="Database server load" ;;
            "") CAUSE="Unknown" ;;
            *) CAUSE="Non-web process: ${top_comm}" ;;
        esac
    fi
}

html_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# Prints an HTML table from tab-separated rows on stdin; arguments are the header cells.
html_table() {
    local cell line
    local -a row
    printf '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-family:sans-serif;font-size:13px;">\n<tr style="background:#eee;">'
    for cell in "$@"; do
        printf '<th align="left">%s</th>' "$(html_escape "${cell}")"
    done
    printf '</tr>\n'
    while IFS=$'\t' read -r -a row; do
        line="<tr>"
        for cell in "${row[@]}"; do
            line+="<td>$(html_escape "${cell}")</td>"
        done
        printf '%s</tr>\n' "${line}"
    done
    printf '</table>\n'
}

# Args: heading for the top of the email
build_html_report() {
    local heading="$1"
    printf '<html><body style="font-family:sans-serif;font-size:14px;">\n'
    printf '<h2>%s</h2>\n' "$(html_escape "${heading}")"
    printf '<p><b>Server:</b> %s<br><b>Load now:</b> %s (threshold %s = %s x %s cores)<br>' \
        "$(html_escape "${HOSTNAME_SHORT}")" "${LOAD_NOW}" "${THRESHOLD}" "${LOAD_THRESHOLD_FACTOR}" "${CORES}"
    if [ "${REPORT_ONLY}" != "true" ]; then
        printf '<b>Samples above threshold:</b> %s%% of the last %s minutes<br>' "${SAMPLE_PCT}" "${WINDOW_MINUTES}"
    fi
    printf '<b>Likely cause:</b> %s</p>\n' "$(html_escape "${CAUSE}")"
    if [ -n "${F2B_WARNING}" ]; then
        printf '<p style="color:#b00;font-weight:bold;">WARNING: %s</p>\n' "$(html_escape "${F2B_WARNING}")"
    fi
    printf '<p><b>fail2ban:</b> banned offenders account for %s%% of attack traffic (%s of %s requests); handling threshold %s%%.</p>\n' \
        "${HANDLED_PCT}" "${BANNED_TOTAL}" "${ATTACK_TOTAL}" "${HANDLED_PERCENT}"

    printf '<h3>CPU by subscription (%% of one core)</h3>\n'
    head -n 10 "${WORK}/sub_cpu" | awk '{ printf "%s\t%s\t%s\n", $1, $2, ($3 == 1) ? "subscription" : "system user" }' \
        | html_table "Subscription / user" "CPU %" "Type"

    if [ -s "${WORK}/sub_requests" ]; then
        printf '<h3>Web requests in the last %s minutes (busiest subscriptions)</h3>\n' "${ANALYSIS_MINUTES}"
        html_table "Subscription" "Requests" < "${WORK}/sub_requests"
    fi

    if [ -s "${WORK}/offenders" ]; then
        printf '<h3>Top offenders</h3>\n'
        head -n 10 "${WORK}/offenders" | awk -F'\t' '{ printf "%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, ($5 == "-") ? "NOT banned" : "banned: " $5 }' \
            | html_table "IP" "Requests" "401/403/404" "Probe hits" "fail2ban"
    fi

    printf '<h3>Top processes by command (%% of one core)</h3>\n'
    head -n 5 "${WORK}/proc_comm_cpu" | awk '{ printf "%s\t%s\n", $1, $2 }' | html_table "Command" "CPU %"
    printf '</body></html>\n'
}

# Args: subject body
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
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
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

# Args: subject body. An explicit SMTP_SERVER wins over the local 'mail' command.
send_email() {
    local subject="$1" body="$2"

    if [ -z "${EMAIL_TO}" ]; then
        log_message "EMAIL_TO is not set, not sending: ${subject}"
        return 0
    fi

    if [ -n "${SMTP_SERVER}" ]; then
        if send_via_smtp "${subject}" "${body}"; then
            log_message "Emailed to ${EMAIL_TO} via SMTP: ${subject}"
            return 0
        fi
        log_message "WARNING: Failed to email ${EMAIL_TO} via SMTP (${SMTP_SERVER}:${SMTP_PORT})"
        return 1
    fi

    if command -v mail >/dev/null 2>&1; then
        if printf '%s\n' "${body}" | mail -a "Content-Type: text/html; charset=UTF-8" -s "${subject}" "${EMAIL_TO}"; then
            log_message "Emailed to ${EMAIL_TO}: ${subject}"
            return 0
        fi
        log_message "WARNING: 'mail' command failed to send to ${EMAIL_TO}"
        return 1
    fi

    log_message "WARNING: Cannot send email - no SMTP_SERVER and no 'mail' command."
    return 1
}

run_analysis() {
    collect_cpu
    collect_banned
    analyze_logs
    analyze_offenders
}

# Args: kind (ALERT|MITIGATED)
raise_incident() {
    local kind="$1" now subject heading
    now=$(date +%s)
    STATE="incident"
    INCIDENT_START="${now}"
    ALERT_SENT="false"

    log_message "INCIDENT ${kind}: load=${LOAD_NOW} threshold=${THRESHOLD} cause=\"${CAUSE}\" banned=${HANDLED_PCT}% of ${ATTACK_TOTAL} attack requests top=$(head -n 3 "${WORK}/sub_cpu" | awk '{ printf "%s(%s%%) ", $1, $2 }')"

    if [ $((now - LAST_ALERT_TS)) -lt $((ALERT_COOLDOWN_MINUTES * 60)) ]; then
        log_message "Alert suppressed: within the ${ALERT_COOLDOWN_MINUTES}-minute cooldown of the previous alert"
        return 0
    fi

    if [ "${kind}" = "MITIGATED" ]; then
        subject="[NOTICE] ${HOSTNAME_SHORT}: attack banned by fail2ban but load still high"
        heading="Load is still high although fail2ban is banning the attack"
    else
        subject="[ALERT] ${HOSTNAME_SHORT}: sustained high CPU load"
        heading="Sustained high CPU load"
    fi
    if send_email "${subject}" "$(build_html_report "${heading}")"; then
        ALERT_SENT="true"
    fi
    LAST_ALERT_TS="${now}"
    LAST_REMINDER_TS="${now}"
}

handle_sustained() {
    local now
    now=$(date +%s)
    run_analysis

    case "${STATE}" in
        normal)
            if [ "${HANDLED}" = "true" ]; then
                STATE="mitigated"
                MITIGATED_SINCE="${now}"
                log_message "Sustained load is attack-like and ${HANDLED_PCT}% of it is banned by fail2ban; no alert"
            else
                raise_incident "ALERT"
            fi
            ;;
        mitigated)
            if [ "${HANDLED}" != "true" ]; then
                raise_incident "ALERT"
            elif [ $((now - MITIGATED_SINCE)) -ge $((WINDOW_MINUTES * 60)) ]; then
                raise_incident "MITIGATED"
            else
                log_message "Load still high; attack is being handled by fail2ban, waiting"
            fi
            ;;
        incident)
            if [ "${ALERT_SENT}" = "true" ] && [ $((now - LAST_REMINDER_TS)) -ge $((REMINDER_HOURS * 3600)) ]; then
                send_email "[REMINDER] ${HOSTNAME_SHORT}: sustained high CPU load continues" \
                    "$(build_html_report "Sustained high CPU load continues")" || true
                LAST_REMINDER_TS="${now}"
            fi
            log_message "Incident ongoing: load=${LOAD_NOW} cause=\"${CAUSE}\""
            ;;
    esac
}

handle_recovered() {
    local now minutes
    now=$(date +%s)
    case "${STATE}" in
        incident)
            minutes=$(((now - INCIDENT_START) / 60))
            log_message "RESOLVED after ${minutes} minutes: load=${LOAD_NOW}"
            if [ "${ALERT_SENT}" = "true" ]; then
                send_email "[RESOLVED] ${HOSTNAME_SHORT}: CPU load back to normal" \
                    "<html><body style=\"font-family:sans-serif;font-size:14px;\"><h2>CPU load back to normal</h2><p>Load is ${LOAD_NOW} (threshold ${THRESHOLD}). The incident lasted about ${minutes} minutes.</p></body></html>" || true
            fi
            ;;
        mitigated)
            log_message "Load recovered after attack was handled by fail2ban"
            ;;
    esac
    STATE="normal"
    MITIGATED_SINCE=0
    INCIDENT_START=0
    ALERT_SENT="false"
}

main() {
    validate_configuration
    umask 077
    mkdir -p "${STATE_DIR}"
    acquire_lock
    WORK=$(mktemp -d)

    if [ "${REPORT_ONLY}" = "true" ]; then
        compute_threshold
        LOAD_NOW=$(cut -d' ' -f1 /proc/loadavg)
        run_analysis
        build_html_report "CPU load report (manual run)"
        return 0
    fi

    record_sample
    evaluate_load
    load_state
    log_message "load=${LOAD_NOW} threshold=${THRESHOLD} over=${SAMPLE_PCT}% of ${SAMPLE_TOTAL} samples state=${STATE}"

    if [ "${WINDOW_COVERED}" != "true" ]; then
        log_message "Collecting samples; less than ${WINDOW_MINUTES} minutes of history so far"
        return 0
    fi

    if [ "${SUSTAINED}" = "true" ]; then
        handle_sustained
    else
        handle_recovered
    fi
    save_state
}

main
