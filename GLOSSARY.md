# Plesk Server Monitoring

Language for the CPU load monitor on AlmaLinux Plesk servers, which detects sustained load, attributes it to subscriptions, and decides whether an administrator needs to be alerted.

## Language

**Sustained load**:
Server load that stays above the load threshold for at least 80% of samples across a 30-minute window. A brief spike is not sustained load.
_Avoid_: High CPU, spike, load average

**Load threshold**:
The load level, scaled by core count, above which a sample counts toward sustained load.
_Avoid_: Limit, cutoff

**Subscription**:
The Plesk unit that owns a set of domains and runs its processes under one system user. It is the unit CPU load is attributed to.
_Avoid_: Website, site, account, customer

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
