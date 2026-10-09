# Contributing

Thanks for helping. Each top-level folder is a standalone script for Plesk servers, so changes are usually small and local. Terms such as *subscription* and *gated update* are defined in [GLOSSARY.md](./GLOSSARY.md); design decisions are in [docs/adr](./docs/adr).

## Workflow

1. Fork the repository and create a branch.
2. Make your change, lint it, and update the docs (see [Documentation](#documentation)).
3. Open a pull request.

There is no build step and no automated test suite for the data-handling scripts. Test in a staging Plesk environment before merging.

## Adding a new script

1. Create a top-level folder named after the task.
2. Add a `.sh` with the self-update block. Add a `.bat` only if the task needs Windows ([ADR 0002](./docs/adr/0002-platform-parity-follows-use-case.md)).
3. Add a `README.md` to the folder using the template in [Documentation](#documentation).
4. Add a row to the Scripts table in the root `README.md`.
5. Add the script to the maintenance matrix and the PID lock / `umask 077` table in [AGENTS.md](./AGENTS.md).
6. Run `shellcheck` on the new script.

## Code conventions

### Windows batch scripts

```batch
@echo off
setlocal enabledelayedexpansion
REM Description: Brief purpose of the script
```

- Use delayed expansion (`!variable!`, not `%variable%`) so paths with parentheses work.
- Quote every path: `"!VARIABLE!"`.
- Use `usebackq` in `FOR /F` loops: `for /F "usebackq tokens=*" %%i in ("!FILE!")`.
- Test with paths containing spaces and parentheses, for example `C:\Program Files (x86)\Plesk`.
- Check `plesk_dir` before use and exit on failure:

  ```batch
  if not defined plesk_dir (
      echo ERROR: plesk_dir environment variable is not set
      exit /b 1
  )
  ```

- Check `errorlevel` after operations that can fail.

### Linux shell scripts

```bash
#!/bin/bash
set -euo pipefail
# Description: Brief purpose of the script
```

- Configure through environment variables with defaults, and validate them: `DAYS=${DAYS:-365}`, then check that required directories exist.
- Use LF line endings (the maintainer edits through WSL).
- **Self-update block:** copy the block from `.github/self-update.template.sh` verbatim, immediately after `set -euo pipefail`, and change only `SCRIPT_RELATIVE_PATH` (the script's path in the repo) and `UPDATE_CHECK_FILE` (unique per script). CI fails on any other difference. If you change the block, change the template first, then every script's copy. Blocks are copied per script, never shared.
- **PID locking** is required when the script can run on a schedule and overlap itself, or writes shared state. Use a PID file and a `trap ... EXIT` that removes it. See `mysql-backup.sh`.
- **`umask 077`** is required when the script writes backups, state or reports that may be sensitive.
- Never hardcode credentials. Windows scripts use the `<password_for_mysql>` placeholder; Linux scripts use `plesk db`.
- MySQL scripts always exclude `information_schema`, `performance_schema` and `phpmyadmin`.
- Reuse the SMTP variable names `SMTP_SERVER`, `SMTP_PORT`, `SMTP_AUTH_USER`, `SMTP_AUTH_PASS`, `SMTP_SECURE` and `SMTP_FROM` for any email relay.

### Script header

Every script starts with a header comment:

```bash
# Purpose: One-line description of what the script does
# Platform: Windows/Linux
# Features:
#   - Feature 1
# Usage: ./script.sh [--update|--self-update] or script.bat
# Environment Variables:
#   - VAR_NAME: Description (default: value)
#   - AUTO_UPDATE: Set to "true" to enable automatic updates (default: false) [Linux only]
#   - UPDATE_CHECK_INTERVAL: Hours between update checks (default: 24) [Linux only]
#   - UPDATE_VERSION: Release tag to install on update (default: latest release) [Linux only]
# Security: Warning about credentials/placeholders if applicable
```

## Testing

Before opening a PR:

1. Lint each changed bash script: `shellcheck path/to/script.sh`
2. Run the CI helpers locally:
   - `.github/scripts/check-self-update.sh`
   - `.github/scripts/test-self-update.sh`
3. Test in a staging or dev Plesk environment and cover the error paths: missing credentials, an empty database list, a missing directory, and concurrent runs (PID lock).
4. Check that files written on Linux have restrictive permissions (600).
5. Test Windows scripts with paths containing spaces and parentheses.

## CI

`.github/workflows/ci.yml` runs four jobs:

- shellcheck on every `.sh` file
- `.github/scripts/check-self-update.sh`: every script's self-update block matches `.github/self-update.template.sh`, `SCRIPT_RELATIVE_PATH` equals the file path, and `UPDATE_CHECK_FILE` is unique
- `.github/scripts/test-self-update.sh`: runs the gated updater against a stubbed `curl` (update, pin, checksum mismatch, no release, bad version)
- actionlint on the workflows

## Releases

Never tag by hand. Add a `CHANGELOG.md` entry under `[Unreleased]` for any script change users should pick up. On pushes to `main` that have unreleased entries, `release-pr.yml` opens or updates a "Release vYYYY.MM.DD" PR that renames `[Unreleased]`. Merging it triggers `release.yml`, which re-runs shellcheck and the drift check, then creates the tag and release with `SHA256SUMS`. This needs the repository setting *Actions → Allow GitHub Actions to create pull requests*.

Docs-only changes need no changelog entry.

## Documentation

Each script's folder `README.md` is the user documentation for that script. The root `README.md` is an index plus the shared install, self-update and security notes. Update the folder README in the same PR as any script change; the [maintenance matrix in AGENTS.md](./AGENTS.md#maintenance-matrix) lists what else to update.

Folder README template:

1. Purpose
2. Platform (and which version is a subset, if any)
3. Prerequisites
4. Usage
5. Configuration (environment variables as a table with defaults, plus command-line options)
6. Scheduling
7. Troubleshooting

Keep the env var table in the README in step with the script header. Update `GLOSSARY.md` when you introduce or change a domain term, and add an ADR in `docs/adr/` only for decisions that are hard to reverse, surprising without context, and the result of a real trade-off.
