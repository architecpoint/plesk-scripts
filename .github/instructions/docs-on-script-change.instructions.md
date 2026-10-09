---
description: 'Keep per-script READMEs in step with script changes'
applyTo: '**/*.{sh,bat}'
---

# Docs on script change

Per-script usage, configuration and troubleshooting live in the `README.md` inside the script's folder. When a script's behaviour, flags or env vars change, update that README in the same change, including its env var table.

The root `README.md` changes only for a new script, a platform change, or the shared install, self-update and security sections.

`AGENTS.md` → **Maintenance Matrix** lists what else moves with each script.
