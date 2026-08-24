# 06 — System Architecture

## 1. Topology

```
┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
│ Flutter app        │   │ Flutter app        │   │ Admin panel        │
│ role: client       │   │ role: coach        │   │ (Flutter web)      │
└─────────┬──────────┘   └─────────┬──────────┘   └─────────┬──────────┘
          │  HTTPS / JSON, JWT access + refresh              │
          └──────────────────┬──────────────────────────────┘
                             ▼
                    ┌──────────────────┐
                    │ Nginx (TLS, rate │
                    │ limit, gzip)     │
                    └────────┬─────────┘
                             ▼
        ┌──────────────────────────────────────────────┐
        │  NestJS API  (single deployable, modular)    │
        │  auth · profile · engine · food · logs ·     │
        │  plans · coach · partner · billing ·         │
        │  notify · admin · consent · audit           │
        └───┬──────────┬───────────┬──────────┬────────┘
            │          │           │          │
            ▼          ▼           ▼          ▼
      PostgreSQL    Redis      BullMQ      Object store
      (primary)    (cache,    (workers:    (S3-compatible:
                   sessions,   renewals,   plan PDFs,
                   rate limit) commissions, coach docs,
                               reminders,   meal photos)
                               retention)
            │
            ▼
   External: Razorpay · Google Play RTDN · MSG91 (DLT SMS) · FCM ·
             Health Connect / HealthKit (on-device) · Food vision API (later)
```

**Not microservices.** One NestJS deployable with hard module boundaries. At your scale (0 users
today, target thousands) microservices would cost you six months and buy you nothing. The module
boundaries are what matter; you can split later along them if you ever need to.

## 2. Module boundaries

| Module | Owns | May not |
|---|---|---|
| `auth` | identity, sessions, OTP, roles | read health data |
| `profile` | Profile, HealthProfile, Measurement, consent capture UI contract | write plans |
| `engine` | pure computation (`packages/diet-engine`) + rule pack loader | touch the DB or HTTP |
| `plans` | plan persistence, revisions, overrides, exports | recompute targets itself |
| `food` | Food, Recipe, HouseholdMeasure, tags, publishing workflow | know about users |
| `logs` | food/water/weight/step logs, diary-day logic | mutate plans |
| `coach` | assignments, check-ins, alerts, chat | read a client field without a consent grant |
| `partner` | attribution, commission ledger, payouts | see client health data |
| `billing` | catalogue, subscriptions, entitlements, webhooks | grant entitlements outside its own resolver |
| `notify` | FCM, SMS, templates, scheduling | select audience by health condition (except clinical) |
| `consent` | consent ledger, grants, expiry, data-subject requests | be bypassed by any other module |
| `audit` | append-only log of privileged reads/writes | be written to by anything other than an interceptor |

Cross-module access is via injected service interfaces only — no direct repository imports across
modules. One shared `packages/contracts` holds DTOs and enums used by app and API alike.

## 3. Key technical decisions (details in doc 07)

- **Flutter + GetX + Clean Architecture** — your existing stack, and correct at this size. Feature-first.
- **NestJS over FastAPI/ASP.NET** — shares TypeScript with `packages/contracts` and the engine, so the
  same engine code can (later) run in the app for offline plan preview. That shared-language argument
  is the deciding factor; all three frameworks are otherwise fine.
- **The engine is a separate package, not a service.** Pure function, no network. Testable in
  milliseconds, embeddable anywhere.
- **Postgres, not MongoDB.** You have money ledgers, entitlements and consent records. Those want
  transactions and constraints. Use `jsonb` columns for the flexible bits (trace, rule pack snapshot).
- **Rule pack as versioned YAML in the repo**, loaded at boot, hash recorded. Not DB rows: you want
  clinical constants to go through code review, not an admin form.
- **Single Flutter codebase for client + coach**, role-gated at the shell. Two apps doubles your
  release surface for no user benefit at this stage.
- **Admin panel as Flutter web** for v1 (one language, one team). Accept that it will feel less
  native than React. Revisit if the admin surface grows past ~15 screens.

## 4. Health data integration

```dart
abstract class HealthDataSource {
  Future<Either<Failure, List<StepSample>>> steps(DateRange r);
  Future<Either<Failure, PermissionState>> ensurePermissions();
  DataSourceLabel get label; // shown in UI: "Health Connect", "Manual"
}
```
Implementations: `HealthConnectDataSource` (Android), `HealthKitDataSource` (iOS),
`ManualStepDataSource` (always available fallback).

**Google Fit is not an implementation option** — it is switched off at the end of 2026 (doc 00 §4).
If the current build uses it, that is a P0 migration.

Rules: steps are read-only; never write to the platform health store in v1; never sync raw health
records to your server beyond daily aggregates; show the source label so users know where a number
came from.

## 5. Caching

| Data | Where | TTL | Invalidation |
|---|---|---|---|
| Food search index | Redis | 24 h | on food publish |
| Plan catalogue + prices | Redis | 1 h | on catalogue change |
| Entitlements | Redis, key `ent:{user}` | 5 min | on subscription event |
| Today's plan | client local (Hive) + Redis | until plan revision changes | on revision bump |
| Rule pack | in-process | process lifetime | on deploy |

Never cache: consent state, commission balances, audit reads.

## 6. Background jobs (BullMQ)

| Job | Schedule | Notes |
|---|---|---|
| `subscription.renewal-check` | hourly | T-7 / T-3 / T-0 notifications; AFA-required flag for >₹15,000 |
| `subscription.expire` | hourly | state transition + entitlement recompute |
| `commission.settle` | daily 02:00 IST | move `held → payable` after the refund window |
| `payout.run` | monthly, 1st | threshold check, TDS, statement generation |
| `plan.weekly-adjust` | weekly per user | v1.1 only; respects §10 of doc 04 |
| `reminders.dispatch` | every 15 min | meal/water reminders in user timezone |
| `retention.purge` | daily 03:00 IST | DPDP retention rules, with 48 h pre-erasure notice |
| `food.derive-condition-tags` | nightly | recomputes `cond:*_ok` from nutrient thresholds |
| `metrics.rollup` | nightly | excludes `is_demo` rows |
| `safety.audit` | weekly | targets near floors, users with 2+ auto-reductions |

Every job is idempotent and takes a distributed lock. Every job logs a start/end with a run id.

## 7. Environments

| Env | Host | Data |
|---|---|---|
| local | docker-compose | seeded, `is_demo = true` |
| staging | Hostinger VPS (separate instance) | synthetic only — never a production dump |
| production | Hostinger VPS | real |

**Never copy production data to staging.** Health data + a lower-security environment is how breaches
happen. Use a synthetic generator (doc 18 §4).

## 8. Scaling notes (when you get there)

The first bottleneck will be food search, then plan generation under a coach bulk-generating 40 plans.
Fixes in order: Postgres full-text with a materialised search table → plan generation moved to a
worker queue with a status poll → read replica. You will not need Kubernetes. Vertical scaling on the
VPS plus these three changes carries you to ~50k MAU comfortably.
