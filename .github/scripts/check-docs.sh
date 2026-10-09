#!/bin/bash
# Purpose: Fail when the docs drift from the scripts.
# Checks: (1) relative links in tracked .md files resolve, (2) every script folder has a README.md,
#         (3) every env var in a script's "Environment Variables" header appears in its folder README.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
fail=0

while IFS= read -r md; do
    dir=$(dirname "${md}")
    while IFS= read -r target; do
        path="${target%%#*}"
        [ -z "${path}" ] && continue
        if [ ! -e "${dir}/${path}" ]; then
            echo "BROKEN LINK: ${md} -> ${target}"
            fail=1
        fi
    done < <(grep -oE '\]\(\.{1,2}/[^)]*\)|\]\(\.{1,2}\)' "${md}" | sed -E 's/^\]\(//; s/\)$//' || true)
done < <(git ls-files '*.md' ':!:.github/skills/*' ':!:.github/agents/*')

while IFS= read -r script; do
    dir=$(dirname "${script}")
    readme="${dir}/README.md"
    if [ ! -f "${readme}" ]; then
        echo "MISSING README: ${readme} (for ${script})"
        fail=1
        continue
    fi
    vars=$(awk '
        /^(#|REM)[[:space:]]+Environment Variables:/ { in_block = 1; next }
        in_block && !/^(#|REM)[[:space:]]/ { in_block = 0 }
        in_block && !/^(#|REM)[[:space:]]+NOTE:/ && /^(#|REM)[[:space:]]+(-[[:space:]]+)?[A-Z][A-Z0-9_]+[[:space:]]*[-:]/ {
            line = $0
            sub(/^(#|REM)[[:space:]]+(-[[:space:]]+)?/, "", line)
            sub(/[[:space:]]*[-:].*/, "", line)
            print line
        }
    ' "${script}")
    for var in ${vars}; do
        if ! grep -q "\`${var}\`" "${readme}"; then
            echo "UNDOCUMENTED ENV VAR: ${var} is in ${script} header but not in ${readme}"
            fail=1
        fi
    done
done < <(git ls-files '*.sh' '*.bat' ':!:.github/*')

if [ "${fail}" -eq 0 ]; then
    echo "Docs checks passed"
fi
exit "${fail}"
