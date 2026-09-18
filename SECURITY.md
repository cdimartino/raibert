# Security policy

## Reporting a vulnerability

Please use GitHub’s private vulnerability reporting for this repository. Do not open a public issue for an unpatched vulnerability or include credentials, player data, or exploitable details in public logs.

Include the affected component, reproduction steps, impact, and any suggested mitigation. Maintainers will acknowledge a report as soon as practical and coordinate disclosure after a repair is available.

## Scope

The leaderboard is a casual, client-authoritative feature. It validates payloads and uses WAF rate limiting, Lambda throttling, idempotency records, and moderation, but a browser score cannot be cryptographically proven. Score manipulation alone is generally an integrity/moderation report; bypasses that expose AWS resources, player data, origin access, or arbitrary execution are security issues.
