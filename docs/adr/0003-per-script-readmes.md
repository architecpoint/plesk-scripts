---
status: accepted
---

# Per-script READMEs with a root index

Each script is meant to be copied onto a server on its own, and its users are sysadmins who care about one tool at a time. Each script folder therefore owns a `README.md` with its purpose, platform, prerequisites, usage, configuration, scheduling and troubleshooting. The root `README.md` is an index: a scripts table, plus the notes that apply to every script (install, self-update, security). Contributor material lives in `CONTRIBUTING.md`, and agent rules in `AGENTS.md`, each stating a fact once and linking to the others.

## Considered options

- **One root README**: one place to search, but it had grown past 500 lines with each script's usage, configuration and troubleshooting scattered across four sections, so it drifted from the scripts and was hard to navigate.
- **A generated docs site**: rejected as too heavy for a collection of shell scripts with no build system.

## Consequences

- Changing a script means editing its folder README, so the maintenance matrix in `AGENTS.md` points at folder READMEs.
- Shared behaviour such as self-update is documented once in the root README and linked from each folder.
- Environment variables are listed in both the script header and the folder README; `check-docs.sh` fails CI when a header variable is missing from the README. Defaults and descriptions are not checked.
