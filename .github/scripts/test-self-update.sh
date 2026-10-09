#!/bin/bash
# Exercises the gated self-update block against a stubbed curl and fake releases.
# Usage: .github/scripts/test-self-update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_REL="pci-dss-scan/pci-dss-scan.sh"
SRC="${ROOT}/${SCRIPT_REL}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mkdir -p "${TMP}/bin" "${TMP}/rel" "${TMP}/work"

# Stub curl: resolves "latest" from LATEST_TAG and serves assets from $REL_DIR/<tag>/
cat > "${TMP}/bin/curl" <<'STUB'
#!/bin/bash
url=""; out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift ;;
        -w) shift ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
case "${url}" in
    */releases/latest)
        if [ -n "${LATEST_TAG:-}" ]; then
            echo "https://github.com/architecpoint/plesk-scripts/releases/tag/${LATEST_TAG}"
        else
            echo "https://github.com/architecpoint/plesk-scripts/releases"
        fi ;;
    */releases/download/*/SHA256SUMS)
        tag="${url#*/releases/download/}"; tag="${tag%%/*}"
        cp "${REL_DIR}/${tag}/SHA256SUMS" "${out}" || exit 22 ;;
    https://raw.githubusercontent.com/*)
        tag="${url#https://raw.githubusercontent.com/*/*/}"; tag="${tag%%/*}"
        cp "${REL_DIR}/${tag}/script.sh" "${out}" || exit 22 ;;
    *) exit 6 ;;
esac
STUB
chmod +x "${TMP}/bin/curl"

make_release() {
    mkdir -p "${TMP}/rel/$1"
    cp "${SRC}" "${TMP}/rel/$1/script.sh"
    echo "# release $1" >> "${TMP}/rel/$1/script.sh"
    echo "$(sha256sum "${TMP}/rel/$1/script.sh" | cut -d' ' -f1)  ${SCRIPT_REL}" > "${TMP}/rel/$1/SHA256SUMS"
}

fresh() {
    cp "${SRC}" "${TMP}/work/s.sh"
    chmod +x "${TMP}/work/s.sh"
}

run_update() {
    ( export PATH="${TMP}/bin:${PATH}" REL_DIR="${TMP}/rel"
      env "$@" bash "${TMP}/work/s.sh" --update 2>&1 ) || true
}

failures=0
check() {
    if [ "$2" = "ok" ]; then echo "PASS: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi
}
unchanged() { cmp -s "${TMP}/work/s.sh" "${SRC}" && echo ok || echo no; }

make_release v2026.10.09
make_release v2026.10.10

fresh; out=$(run_update LATEST_TAG=v2026.10.10)
grep -q "release v2026.10.10" "${TMP}/work/s.sh" && check "latest release is installed" ok || check "latest release is installed" no

fresh; out=$(run_update LATEST_TAG=v2026.10.10 UPDATE_VERSION=v2026.10.09)
grep -q "release v2026.10.09" "${TMP}/work/s.sh" && check "UPDATE_VERSION pins an older release" ok || check "UPDATE_VERSION pins an older release" no

fresh; echo "deadbeef  ${SCRIPT_REL}" > "${TMP}/rel/v2026.10.10/SHA256SUMS"
out=$(run_update LATEST_TAG=v2026.10.10)
check "checksum mismatch keeps current version" "$(unchanged)"
echo "${out}" | grep -q "Checksum verification failed" && check "checksum mismatch is reported" ok || check "checksum mismatch is reported" no
make_release v2026.10.10

fresh; echo "abc  other/file.sh" > "${TMP}/rel/v2026.10.10/SHA256SUMS"
out=$(run_update LATEST_TAG=v2026.10.10)
check "missing checksum entry keeps current version" "$(unchanged)"
make_release v2026.10.10

fresh; out=$(run_update)
check "no release keeps current version" "$(unchanged)"
echo "${out}" | grep -q "No release to install" && check "no release is reported" ok || check "no release is reported" no

fresh; out=$(run_update LATEST_TAG=v2026.10.10 'UPDATE_VERSION=../main')
check "invalid UPDATE_VERSION keeps current version" "$(unchanged)"

fresh; out=$(run_update LATEST_TAG=v2026.10.10 GITHUB_BRANCH=develop)
echo "${out}" | grep -q "GITHUB_BRANCH is no longer used" && check "GITHUB_BRANCH notice is logged" ok || check "GITHUB_BRANCH notice is logged" no

[ "${failures}" -eq 0 ] || { echo "${failures} check(s) failed"; exit 1; }
echo "All self-update checks passed"
