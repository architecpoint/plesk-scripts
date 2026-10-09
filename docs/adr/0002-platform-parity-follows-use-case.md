---
status: accepted
---

# Platform parity follows the script's use case

Strict `.bat`/`.sh` parity is not required. Only the scripts that already ship both versions (`mysql-backup`, `pci-dss-scan`) keep their pair in step, and the README states where the Windows version is a subset. New scripts are Linux-only by default, because the servers are overwhelmingly Linux; a Windows version is added only when the task needs it.

Likewise, conventions such as the PID lock and `umask 077` apply when the script needs them (it can overlap itself, or writes shared state or sensitive files), not to every script. Forcing them everywhere would add code with no purpose to read-only scanners.
