# PCI-DSS Security Header Compliance Scanner

Scans a website for the security header issues most often flagged by PCI-DSS compliance tools (for example PayPal's `paypal.managepci.com` scanner).

## Purpose

Checks banner disclosure, cookie flags, caching headers and other best-practice headers across common sensitive paths, and exits with the number of failures so it can gate a CI/CD pipeline.

## Platform

| Script | Platform | Notes |
| --- | --- | --- |
| `pci-dss-scan.sh` | Linux | Full feature set, self-update |
| `pci-dss-scan.bat` | Windows | Documented subset: basic checks only, no self-update |

## Prerequisites

- `curl` (all HTTP requests use it)
- `sha256sum` for Linux self-update
- On Windows, a terminal that supports ANSI colours (Windows Terminal or PowerShell)

## What it checks

- `X-Powered-By`, `Server` and other banner-disclosure headers (PCI DSS Req. 2.2 / 6.5)
- All `Set-Cookie` headers for missing `Secure`, `HttpOnly` and `SameSite` flags
- `Cache-Control` on sensitive pages (login, checkout, cart, admin) and public pages
- Best-practice headers: `X-Frame-Options`, `Strict-Transport-Security`, `Content-Security-Policy`, and others
- Multiple paths automatically: homepage, WordPress login, WooCommerce checkout, cart, registration, admin, plus your own via `EXTRA_PATHS`

## Usage

**Linux:**

```bash
# Scan a target
./pci-dss-scan.sh https://example.com

# Scan with auto-update enabled
AUTO_UPDATE=true ./pci-dss-scan.sh https://example.com

# Add extra paths to test (space-separated)
EXTRA_PATHS="/members/ /sign-up/" ./pci-dss-scan.sh https://example.com
```

**Windows:**

```cmd
pci-dss-scan.bat https://example.com
```

**Interpreting results:**

- `[PASS]`: the check passed; no action required
- `[FAIL]`: a PCI-DSS required control is missing or misconfigured; remediate before re-scanning
- `[WARN]`: a best-practice header or flag is absent; review and apply if possible
- The exit code equals the number of `[FAIL]` results (`0` means all clear)

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `TARGET_URL` | none | Target URL; required unless passed as the first argument |
| `EXTRA_PATHS` | none | Space-separated extra URL paths for cookie and header checks |
| `AUTO_UPDATE` | `false` | `true` enables automatic updates (Linux only) |
| `UPDATE_CHECK_INTERVAL` | `24` | Hours between update checks (Linux only) |
| `UPDATE_VERSION` | latest release | Release tag to install on update (Linux only) |

**Command-line options:**

- First argument: target URL (overrides `TARGET_URL`)
- `--update` or `--self-update`: update the script to the latest release (Linux only)

See the [root README](../README.md#self-update) for how self-update works.

## Scheduling

Usually run on demand or as a CI step. It is read-only and needs no PID lock.

## Troubleshooting

**Site is unreachable**

```bash
curl -I https://example.com
```

**Cookies not detected on protected or login pages**

- The scanner makes unauthenticated requests, so authenticated session cookies only appear after login
- Log in with a browser, capture the cookies with dev tools, and compare the flags manually
- Or use `EXTRA_PATHS` for pages that set cookies before authentication

**Some paths return 404 and are skipped**

- Confirm the path exists on the target site
- Add the correct paths: `EXTRA_PATHS="/give/ /events/" ./pci-dss-scan.sh https://example.com`

**ANSI colours not displaying in Windows CMD**

- Run from Windows Terminal or PowerShell
- Or write to a file: `pci-dss-scan.bat > results.txt`
