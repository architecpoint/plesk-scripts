# Plesk Scripts

Language for the standalone scripts that back up, clean, scan and monitor Plesk servers, and for how those scripts are released and kept up to date.

## Language

### Plesk

**Subscription**:
The Plesk unit that owns a set of domains and runs its processes under one system user. It is the unit CPU load is attributed to.
_Avoid_: Website, site, account, customer

**Vhosts root**:
The directory under which Plesk keeps every subscription's files, by default `/var/www/vhosts`.
_Avoid_: Web root, sites directory

### Updating

**Self-update**:
A script replacing itself with a newer published version, on request or automatically.
_Avoid_: Auto-upgrade, patch

**Gated update**:
A self-update that installs only a script published in a release and verified against that release's checksums. If verification fails, the current version is kept.
_Avoid_: Safe update, signed update

**Release**:
A dated, tagged snapshot of every script, published with checksums. It is the only source a self-update installs from.
_Avoid_: Version, build, deploy

**Platform parity**:
Keeping the Windows and Linux versions of a script in step. It applies only to scripts that already ship both versions, and the Windows version may be a documented subset.
_Avoid_: Cross-platform support

### Backups and retention

**Retention**:
How long a backup is kept before it becomes eligible for deletion, with a minimum number of the newest backups per domain always kept.
_Avoid_: Expiry, TTL

**Dry run**:
A run that reports what would be deleted without deleting anything.
_Avoid_: Preview mode, simulation

### Monitoring

**Sustained load**:
Server load that stays above the load threshold for at least 80% of samples across a 30-minute window. A brief spike is not sustained load.
_Avoid_: High CPU, spike, load average

**Load threshold**:
The load level, scaled by core count, above which a sample counts toward sustained load.
_Avoid_: Limit, cutoff

**Offender**:
An IP address responsible for attack-like traffic against a subscription, either because a fail2ban jail has banned it or because its request pattern looks like a bot scan or attack.
_Avoid_: Attacker, bad IP

**Banned offender**:
An offender currently in the banned list of any fail2ban jail except the SSH jail.
_Avoid_: Blocked IP

**Handled attack**:
An attack where banned offenders account for at least 80% of the attack traffic, so fail2ban is already containing it and no alert is needed.
_Avoid_: Mitigated, resolved

**Incident**:
One continuous period of sustained load, from the moment it is detected until load drops back below the threshold.
_Avoid_: Event, outage
