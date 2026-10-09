#!/bin/bash
set -euo pipefail
# Purpose: Fail CI when a script's embedded self-update block drifts from the template
# Usage: .github/scripts/check-self-update.sh   (run from anywhere inside the repo)
#
# Checks for every tracked *.sh outside .github/:
#   - the block from the SELF-UPDATE banner to the end of self_update() matches
#     .github/self-update.template.sh (comments, blank lines and trailing spaces ignored;
#     SCRIPT_RELATIVE_PATH and UPDATE_CHECK_FILE masked)
#   - SCRIPT_RELATIVE_PATH equals the script's real path in the repo
#   - UPDATE_CHECK_FILE is a unique /tmp/ path
#   - --update/--self-update handling and the AUTO_UPDATE tail are present

REPO_ROOT="$(git rev-parse --show-toplevel)"
TEMPLATE=".github/self-update.template.sh"
failures=0

fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# Print the normalized comparable core of a script's self-update block
normalized_core() {
    awk '
        /SELF-UPDATE FUNCTIONS/ { on = 1 }
        on { print }
        on && /^self_update\(\) *\{/ { in_fn = 1 }
        on && in_fn && /^}/ { exit }
    ' "$1" | sed -E '
        s/[[:space:]]+$//
        /^[[:space:]]*#/d
        /^$/d
        s|^(SCRIPT_RELATIVE_PATH=).*|\1X|
        s|^(UPDATE_CHECK_FILE=).*|\1X|
    '
}

cd "${REPO_ROOT}"

expected="$(normalized_core "${TEMPLATE}")"
if [ -z "${expected}" ]; then
    echo "ERROR: could not extract the self-update block from ${TEMPLATE}"
    exit 2
fi

declare -A seen_check_files=()

while IFS= read -r script; do
    case "${script}" in
        .github/*) continue ;;
    esac

    if ! grep -q 'SELF-UPDATE FUNCTIONS' "${script}"; then
        fail "${script}: missing self-update block"
        continue
    fi

    if [ "$(normalized_core "${script}")" != "${expected}" ]; then
        fail "${script}: self-update block differs from ${TEMPLATE}"
        diff <(echo "${expected}") <(normalized_core "${script}") | head -20 || true
    fi

    relative_path="$(sed -nE 's/^SCRIPT_RELATIVE_PATH="([^"]*)".*/\1/p' "${script}" | head -1)"
    if [ "${relative_path}" != "${script}" ]; then
        fail "${script}: SCRIPT_RELATIVE_PATH is '${relative_path}', expected '${script}'"
    fi

    check_file="$(sed -nE 's/^UPDATE_CHECK_FILE="([^"]*)".*/\1/p' "${script}" | head -1)"
    case "${check_file}" in
        /tmp/.*) ;;
        *) fail "${script}: UPDATE_CHECK_FILE '${check_file}' must be a /tmp/.* path" ;;
    esac
    if [ -n "${seen_check_files[${check_file}]:-}" ]; then
        fail "${script}: UPDATE_CHECK_FILE '${check_file}' is also used by ${seen_check_files[${check_file}]}"
    fi
    seen_check_files["${check_file}"]="${script}"

    if ! grep -q -- '"--update"' "${script}" || ! grep -q -- '"--self-update"' "${script}"; then
        fail "${script}: missing --update/--self-update handling"
    fi
    if ! grep -q 'AUTO_UPDATE:-false' "${script}"; then
        fail "${script}: missing AUTO_UPDATE tail"
    fi
done < <(git ls-files '*.sh')

if [ "${failures}" -gt 0 ]; then
    echo "${failures} self-update check(s) failed"
    exit 1
fi

echo "OK: all self-update blocks match ${TEMPLATE}"
