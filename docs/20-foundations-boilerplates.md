# 20 — Foundations, Boilerplates & Package Manifest

Verified August 2026. Every licence below must be re-checked before you ship — licences change
(the `ifct2017` npm packages went AGPL-3.0 in May 2025, mid-project, for anyone depending on them).

---

## 1. The honest summary

| Layer | Foundation exists? | Time saved |
|---|---|---|
| Backend scaffolding (auth, config, i18n, uploads, Docker, CI, e2e harness) | **Yes, good one** | 10–15 days |
| Admin panel | **Yes, and it beats the current plan** | 6–9 days |
| Flutter app skeleton | **No — nothing usable** | 0 |
| Billing / entitlements plumbing | **Yes (managed service)** | 7–12 days |
| Health data (steps) | **Yes, one package** | 4–6 days |
| Packaged-food database | **Yes (Open Food Facts)** | 5–8 days |
| **Indian home-cooked food DB with household measures** | **No** | 0 |
| **Diet engine + rule pack + safety layer** | **No** | 0 |
| **Consent/RBAC layer, commission ledger** | **No** | 0 |

The bottom four rows are ~60 % of the work and 100 % of what makes Eatzify defensible. No repository
will hand them to you. Everything above them is plumbing you should absolutely not hand-write.

Realistic effect on Phase 1 (doc 17: 8–10 weeks): **down to roughly 6–7 weeks**, if you adopt the
backend boilerplate and AdminJS/Refine and resist the urge to fork a nutrition app.

---

## 2. Backend foundation — adopt this

**`brocoders/nestjs-boilerplate`** — MIT, actively maintained, properly documented at
`brocoders.github.io/nestjs-boilerplate`.

Ships: NestJS + TypeORM + Postgres, hexagonal-architecture split (so the DB is swappable), JWT auth
with email sign-in/sign-up, social sign-in (Apple/Facebook/Google), admin + user roles, `@nestjs/config`,
nodemailer, i18n via `nestjs-i18n`, file uploads with local and S3 drivers, seeds, unit + E2E test
harness, Docker, GitHub Actions CI.

That list maps almost exactly onto epics E1 and E10 in doc 17.

**Before writing your first Eatzify line, delete:** the Mongoose/document-database path (you're
Postgres-only, ADR-003), social sign-in you don't need (phone OTP is your primary auth in India),
and any example module. A boilerplate you haven't pruned becomes a codebase you don't understand.

Runner-up: `NarHakobyan/awesome-nest-boilerplate` — RS256 JWT, RBAC, Swagger, i18n interceptors,
a CQRS example. Cleaner RBAC starting point, less documentation.

---

## 3. Admin panel — this changes ADR-006

ADR-006 chose Flutter web to avoid introducing React. Two options beat it on schedule:

**`AdminJS`** (~8k stars) auto-generates a full CRUD admin from your TypeORM models, with a NestJS
adapter. Filters, search, validation, RBAC, file upload, import/export and audit-log plugins included.
Custom React components can override any generated view.

For the nutrition database — the screen you'll use most and care about least — this is a working admin
in a day rather than a week. Point it at `foods`, `recipes`, `household_measures`.

**`Refine`** (MIT, ~33k stars, v5 as of Feb 2026, React 19 + TanStack Query) is the choice if the admin
becomes a real product surface: headless, framework-agnostic access control with RBAC/ABAC, a
`@refinedev/nestjs-query` data provider, and built-in Ant/MUI/Mantine integrations.

**Recommendation:** AdminJS for internal CRUD now, Refine later for the coach-verification, ticketing
and metrics surfaces where the UX matters. This also gives you the React/TypeScript practice you're
already working on, on a low-risk internal tool rather than the customer-facing app.

Revise ADR-006 rather than silently diverging from it.

---

## 4. Flutter — there is no foundation, and that's fine

Every GetX "clean architecture boilerplate" on GitHub is a 1–10 star personal project, most last
touched in 2024 or earlier, several still on Flutter 2.x. Adopting one means inheriting an unmaintained
stranger's architecture decisions to save two days of folder creation. Don't.

Instead: `get_cli` (`get create project`) for scaffolding, then build the tree in doc 14 §2 yourself.
The Flutter time saving comes from packages, not templates.

---

## 5. OpenNutriTracker — read it, do not copy it

`simonoppowa/OpenNutriTracker` — Flutter calorie tracker, clean-architecture split, ~1.4k stars,
active (v1.4.0 releases in 2026).

**Licence: GPL-3.0.** Copying its code into a commercial closed-source app means your app becomes
GPL-3.0. Do not fork it, do not lift widgets from it, do not paste its calculation code.

Read it for three things it does better than your current build:
1. **It cites its sources in-app.** A "Sources & References" screen linking every paper — calorie
   targets from IOM 2005, BMI from WHO, macros from WHO TRS 916, activity burn from the 2024
   Compendium. This is exactly the posture doc 05 §9 asks for, and it's a trust feature, not overhead.
2. **Its fasting timer opens with an eating-disorder content warning** linking support organisations.
   That is the doc 05 §6 standard, shipped by someone with no commercial incentive to be careful.
3. **Offline-first architecture** with the record kept on-device.

Note it uses `flutter_bloc` + `get_it`, not GetX — so even the patterns don't transfer directly.

Same warning for `wger` (AGPL) and most FOSS fitness apps: copyleft by default. Check the licence
before you read the code, not after.

---

## 6. Food data

| Source | Covers | Licence | Use for |
|---|---|---|---|
| **Open Food Facts** (~4M products, `in.openfoodfacts.org`) | Packaged/barcoded food | **ODbL v1.0**, contents under DbCL, images CC-BY-SA | Barcode scanning of Indian packaged goods |
| **INDB** (1,095 items + 1,014 composite recipes) | Indian home cooking | Open access, verify reuse terms | The plan engine's food pool |
| **IFCT 2017** (528–542 foods, 151 nutrients) | Indian raw foods, measured | ICMR-NIN publication | Source of truth for raw items |
| `ifct2017` npm packages | Same as IFCT | **AGPL-3.0 — do not link** | Nothing. Write your own loader (ADR-012). |

Open Food Facts practicalities: free API, no key, no rate limit for reasonable use, nightly full dumps
(JSON/CSV/SQLite/Parquet). Send a real `User-Agent`, cache by barcode, use the dumps for bulk work
rather than hammering the API, and attribute per the licence. ODbL carries a share-alike obligation on
derived *databases* — get a lawyer's read on whether your curated food table triggers it before launch.

**What none of these give you: household measures.** "1 katori dal = 150 g" is not in any open
dataset. That table is manual work, it's the single most India-specific asset in the product, and it's
why doc 17 says build E2 first and in parallel.

---

## 7. Flutter package manifest

```yaml
dependencies:
  # State, routing, DI — your existing stack
  get: ^4.6.6
  dartz: ^0.10.1

  # Network & storage
  dio: ^5.7.0
  hive_ce: ^2.0.0              # hive is unmaintained; hive_ce is the community fork
  flutter_secure_storage: ^9.2.2

  # Health — HealthKit (iOS) + Health Connect (Android) behind one API.
  # Dropped Google Fit at v11.0.0 because Google closed signups (confirms doc 00 §4).
  health: ^13.3.1

  # Billing — see §8 for the entitlement-ownership caveat
  purchases_flutter: ^8.0.0    # RevenueCat
  razorpay_flutter: ^1.4.0     # web/UPI checkout

  # UI
  flutter_screenutil: ^5.9.3
  fl_chart: ^0.69.0            # weight trend, macro rings
  cached_network_image: ^3.4.1
  shimmer: ^3.0.0              # skeleton loaders (NFR-8)

  # Logging & scanning
  mobile_scanner: ^6.0.0       # barcode → Open Food Facts
  image_picker: ^1.1.2

  # Notifications
  firebase_messaging: ^15.1.0
  flutter_local_notifications: ^18.0.0
  timezone: ^0.10.0            # required for correct IST reminder scheduling

  # Platform
  intl: ^0.19.0
  sentry_flutter: ^8.9.0
  package_info_plus: ^8.1.0    # fixes the hardcoded "Version 1.0.0" (doc 15 D-07)

dev_dependencies:
  build_runner: ^2.4.13
  json_serializable: ^6.8.0
  freezed: ^2.5.7              # immutable entities + copyWith, per doc 14 §3
  mocktail: ^1.0.4
  golden_toolkit: ^0.15.0
  very_good_analysis: ^6.0.0   # stricter lints than flutter_lints
```

Pin exact versions in `pubspec.lock` and commit it. Re-check every version at install time — these
were current in August 2026.

## 8. Backend package manifest

```jsonc
{
  "@nestjs/common": "^11",
  "@nestjs/config": "^4",
  "@nestjs/throttler": "^6",        // rate limits per docs/09 §10
  "@nestjs/bullmq": "^11",          // the job list in docs/06 §6
  "typeorm": "^0.3",
  "pg": "^8",
  "ioredis": "^5",
  "class-validator": "^0.14",
  "class-transformer": "^0.5",
  "nestjs-i18n": "^10",
  "nestjs-pino": "^4",              // structured logs WITH redact paths — see below
  "helmet": "^8",
  "razorpay": "^2",
  "googleapis": "^144",             // Play Developer API for RTDN + purchase verification
  "js-yaml": "^4",                  // rule-pack loader
  "zod": "^3",                      // rule-pack schema validation at boot
  "@adminjs/nestjs": "^6",
  "@adminjs/typeorm": "^5",
  "firebase-admin": "^13",
  "@sentry/nestjs": "^8"
}
```

**Configure `nestjs-pino` redaction on day one**, before there's anything to leak:

```ts
redact: {
  paths: [
    'req.headers.authorization', 'req.headers.cookie',
    '*.phone_e164', '*.email', '*.display_name',
    '*.weight_kg', '*.height_cm', '*.bmi',
    '*.conditions', '*.food_allergies', '*.screening',
    '*.otp', '*.pan_last4',
  ],
  censor: '[redacted]',
}
```
This is the mechanical half of `CLAUDE.md` hard rule 5. The lint rule catches new code; this catches
everything else.

---

## 9. RevenueCat — the one decision that needs care

`purchases_flutter` handles server-side receipt validation, cross-platform subscription status,
webhooks, and conversion/MRR/churn analytics. It removes the most bug-prone code in the whole app.

**But it conflicts with doc 11 §4**, which says entitlements are resolved by *your* server. Keep that
rule. The correct wiring:

```
Play purchase → RevenueCat validates → webhook → your API writes subscriptions +
                recomputes entitlements → app reads entitlements from GET /auth/me
```

RevenueCat is the *validator*, never the source of truth your app queries. Reasons: your entitlements
include things RevenueCat can't know (partner-granted coaching seats, admin comps, safety features
that are never gated), you must not be unable to serve a paying user if a third party has an outage,
and doc 13 means you should not hand a vendor more user identity than it needs.

Check RevenueCat's current pricing tiers before committing — the free tier's revenue ceiling has moved
before, and at Indian ARPU their percentage-of-revenue model needs a look against Play's 15 % on top.
Fallback: `in_app_purchase` (official Flutter plugin) plus your own verification against the Play
Developer API. Roughly 5–8 extra days and a permanent maintenance surface.

---

## 10. What to build, in order, given all of the above

1. Fork `brocoders/nestjs-boilerplate`, prune it, get auth + Postgres + CI green. **~3 days.**
2. Point AdminJS at the food tables. Now you have a nutrition-DB admin. **~1 day.**
3. Import INDB → `foods`/`recipes` with the Atwater constraint on. Start the household-measures table
   by hand. **This is the long pole — start it now and keep it running in parallel.**
4. Write `packages/diet-engine` from doc 04 with the golden vectors from doc 16. No dependencies, no
   shortcuts, nobody else's code. **~5–7 days.**
5. Scaffold Flutter with `get_cli`, build the one shell from doc 14 §1, wire `health` and `dio`.
6. RevenueCat + Razorpay behind your own entitlement resolver.
7. Consent/RBAC layer from docs 10 and 13. Hand-written, no library — casbin can express the rules but
   not the consent-grant expiry, and you need the audit trail more than you need the policy engine.
