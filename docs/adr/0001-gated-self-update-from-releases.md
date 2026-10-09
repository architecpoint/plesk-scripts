---
status: accepted
---

# Gated self-update from verified releases

Bash scripts update themselves and often run as root from cron, so the update source is a root-level trust boundary. Updating from the `main` branch with no verification means anyone who can push to `main` runs code as root on every server with `AUTO_UPDATE=true`. Scripts will instead update only from a published GitHub release: they resolve the latest release tag (or `UPDATE_VERSION` if set), download the script from that tag, and verify it against the release's `SHA256SUMS` before replacing themselves. If there is no release or the checksum fails, they abort and keep the current version.

Releases are produced by a workflow rather than by hand. Tags are date-based (`vYYYY.MM.DD`, `-2` for a second release the same day), one tag covers every script, and a release only gets a `SHA256SUMS` if shellcheck and the self-update drift check pass.

## Considered options

- **Keep updating from `main`**: simplest, but one compromised or mistaken push reaches every server.
- **Signed `SHA256SUMS` (minisign/GPG)**: protects against a compromised repo, not just corruption. Deferred, since it needs key management; it can be layered on later.

## Consequences

- A new script is not updatable until the next release is cut.
- `GITHUB_BRANCH` is removed; servers on old copies update once more after the first release to pick up the gated updater.
- Each script keeps its own copy of the self-update block (scripts must stay standalone single files); CI checks the copies against a shared template instead of sharing code.
