# 18 — Ops Runbook

## 1. Environments

| | local | staging | production |
|---|---|---|---|
| Host | docker-compose | Hostinger VPS (separate) | Hostinger VPS |
| DB | Postgres 16 container | own instance | own instance, private network only |
| Data | seeded, `is_demo=true` | **synthetic only** | real |
| Secrets | `.env.local` | injected at deploy | injected at deploy |
| Payments | Razorpay test + Play internal test | same | live |
| Push | FCM dev project | FCM staging | FCM prod |

Never restore a production dump to staging. Health data plus a lower-security environment is the
textbook breach path, and under DPDP it is a reportable one.

## 2. Deploy

```
main branch → CI (lint, typecheck, unit, golden vectors, migration dry-run)
            → build container
            → staging deploy → smoke suite
            → manual approval
            → production deploy (blue/green on the VPS: two systemd units + nginx upstream switch)
            → post-deploy smoke → auto-rollback on failure
```

Migrations run **before** the new container takes traffic, and must be backwards-compatible with the
previous release (expand/contract: add columns nullable, backfill, switch reads, drop later — never in
one release).

App releases: Play internal test → closed track (beta coaches) → staged rollout 10 % → 50 % → 100 %.
Never a 100 % rollout on a release that touches the engine or billing.

## 3. CI gates (a PR cannot merge without)

- `dart analyze` and `eslint` clean, zero new warnings
- Unit tests pass; engine coverage ≥ 95 %
- Golden vectors byte-identical unless the rule pack version was bumped **and** a `reviewed_by` is set
- RBAC matrix tests pass (all of doc 10)
- No PII-shaped literals in new log statements (custom lint)
- Migration dry-run succeeds on a copy of the staging schema
- `.env.example` updated if a new variable was introduced
- Governing doc section cited in the PR body

## 4. Synthetic data generator

`scripts/gen-synthetic.ts` — 500 profiles across the full input space (doc 16 §4), Indian-name
generator, plausible weight series with realistic noise, food logs with realistic adherence
distributions (a third of users at 80 %+, a third at 40–70 %, a third dropping off in week two).
Used for staging, load tests, and the nightly engine sweep.

## 5. Observability

| Layer | Tool | Key signals |
|---|---|---|
| API | structured JSON logs + request id | p50/p95/p99 latency, 4xx/5xx by code |
| Errors | Sentry (server + Flutter) | new-issue alerts, crash-free-session rate |
| Uptime | external monitor, 1 min | `/health` (liveness) and `/ready` (DB+Redis) |
| Jobs | BullMQ dashboard + log lines | queue depth, failure rate, run duration |
| DB | pg_stat_statements | slow queries > 200 ms, connection saturation, bloat |
| Business | nightly rollup table | signups, activations, plans generated, MRR, churn — `is_demo` excluded |

**Alert (page someone):** 5xx rate > 2 % for 5 min · plan generation failure rate > 1 % ·
payment webhook failures > 3 in 10 min · commission reconciliation mismatch · backup job failed ·
any `PLAN_GATE_*` bypass detected · any target issued below a doc 05 floor.

**Alert (ticket, not page):** `insufficient_food_coverage` > 2 % of generations · queue depth > 1,000 ·
disk > 80 % · a coach access denial spike (usually means grants are expiring en masse).

## 6. Backups

- Postgres: `pg_dump` nightly + WAL archiving; encrypted with a key not stored on the VPS; 30-day
  retention; off-VPS storage.
- Object store: versioning on, lifecycle rule matching doc 13's retention table.
- **Quarterly restore drill.** Restore into a scratch instance, run the smoke suite, record the RTO in
  a log file. An untested backup is not a backup; this is the single most commonly skipped control and
  the one you will most regret skipping.

## 7. Incident response

Severities: **S1** data loss / breach / payments down · **S2** core flow broken (plan generation, login)
· **S3** degraded · **S4** cosmetic.

S1/S2 flow: acknowledge → declare → stabilise (rollback first, diagnose second) → communicate
(in-app banner + status note) → resolve → **blameless post-mortem within 72 h** with an ADR entry if a
decision changed. For any incident touching health data, run the doc 13 §8 breach clock in parallel
from minute zero — you can always stand it down; you cannot recover lost hours.

Runbook stubs to write before launch (one page each): DB failover · Redis down (degrade to no-cache,
do not fail requests) · payment provider outage (queue and retry, never double-charge) · Play RTDN
backlog · FCM key rotation · a coach reporting they can see the wrong client's data (treat as S1
immediately).

## 8. Secrets and access

- Secrets in a manager or as deploy-time env vars; never in the repo, never in the container image.
- Rotate quarterly and on any team change.
- Production DB access: named accounts only, no shared `postgres` login, all access logged.
- SSH: keys only, no passwords, fail2ban, non-standard port, root login disabled.
- 2FA on Play Console, Razorpay, DNS, VPS panel, GitHub. DNS and Play Console are the two accounts
  whose compromise you cannot recover from — treat them accordingly.

## 9. Cost model (indicative, monthly, first year)

| Item | ₹ |
|---|---|
| VPS (production, 4 vCPU / 8 GB) | 1,200–2,000 |
| VPS (staging, small) | 500–800 |
| Object storage + egress | 300–800 |
| SMS/OTP (DLT, MSG91) | 0.15–0.25 per SMS → ~1,500 at 1k signups |
| FCM | free |
| Sentry / monitoring | 0–2,000 |
| Domain + TLS | ~100 |
| Food vision API (Phase 3) | usage-based, model before enabling |
| **Total, pre-scale** | **~₹4,000–7,000** |

The dominant cost at low scale is OTP SMS, which scales with signups, not revenue. Cap OTP requests
per number per day (doc 09 §10) or a bot will spend your infra budget for you.
