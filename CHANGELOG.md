# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not follow semantic versioning (it is a script collection, not a versioned package).

## [Unreleased]

### Added

- CI jobs `Gated self-update behaviour` (`.github/scripts/test-self-update.sh`, runs the updater against a stubbed `curl`) and `Lint workflows` (actionlint).

## v2026.10.09

### Added

- `AGENTS.md`, maintenance matrix, CI workflow, issue/PR templates, and this changelog (AI-ready repo setup).
- `monitor-cpu-load/monitor-cpu-load.sh`: sustained CPU load monitor for AlmaLinux Plesk servers with per-subscription attribution, attack detection, fail2ban-aware alert suppression, and email alerts.
- Each Linux bash script embeds its own copy of the self-update block; `.github/self-update.template.sh` is the canonical source and the CI job `Self-update block drift check` (`.github/scripts/check-self-update.sh`) fails if a copy drifts.
- `GLOSSARY.md` with the domain terms for the CPU load monitor.
- ADRs in `docs/adr/` for gated self-update from releases and for platform parity following the script's use case.

### Changed

- Self-update is gated: scripts install only a GitHub release (latest, or `UPDATE_VERSION` to pin) after verifying it against the release's `SHA256SUMS`. `GITHUB_BRANCH` is removed (a notice is logged if set). **Servers must update once more after the first release** (`--update` still pulls from the old source until then; the first release is cut immediately after this merges).
- Release automation: `release-pr.yml` opens a "Release vYYYY.MM.DD" PR on pushes to `main`; merging it runs `release.yml`, which creates the tag and release with `SHA256SUMS`.
- PID locking and `umask 077` are documented as conditional conventions, with a per-script table in `AGENTS.md`; platform parity applies only to scripts that already have a `.bat` pair.

## 2026-04-26

### Added

- Monitoring script for domain hosting settings (ASP.NET) with email alerts (`monitor-domain-hosting/`).
- Security review references; enhanced MySQL backup scripts.

## 2026-04-22

### Added

- Essential Plugin supply-chain attack scanner for WordPress (`essential-plugin-malware-scan/`).
- Plain-text email report output for the scanner.

## 2026-03-15

### Changed

- PCI-DSS scanner improvements (`pci-dss-scan/`).

## 2026-03-01

### Added

- PCI-DSS security header compliance scanner for Windows and Linux (`pci-dss-scan/`).

## 2025-11-01

### Added

- Dry-run mode for the WordPress backup cleanup script.
- Self-update functionality for MySQL and WordPress backup scripts.
- Comprehensive GitHub Copilot documentation for Plesk scripts.

## 2022-12-31 and earlier

### Added

- Initial `mysql-backup.sh` and `mysql-backup.bat` scripts.
- Initial `remove-wordpress-backup` script.
