# Project state

**Purpose: answer "where are we?" without reading the repo.** Overwrite this file when state
changes — it is a snapshot, not a history. History lives in `DECISIONS.md`.

Last verified: 2026-08-24 (auth session) · verified by running the commands in the Checks table, not by reading code.

## Shape

```
health_pro/              monorepo · git, 15 commits on main
├── CLAUDE.md            Flutter scope + layout table
├── .claude/             1 settings.json · 9 rules · 7 skills · 2 agents
├── docs/                22 numbered specs + this file + DECISIONS.md + PLACEMENT.md
├── lib/ test/           Flutter — auth + onboarding built, 67 tests
└── api/                 backend (NestJS boilerplate fork)
    ├── config/rule-packs/v1.0.0.yaml
    ├── packages/diet-engine/     the engine
    ├── src/auth/                 email flow (boilerplate) + phone OTP
    └── src/modules/engine/       loader + zod schema + EngineService
```

## Status

| Area | State | Evidence |
|---|---|---|
| Claude config | **done** | 9 path-scoped rules, globs verified against the real tree |
| Docs | **done** | 21 specs, doc 20 added this session |
| Rule pack v1.0.0 | **built, unapproved** | validates at boot; needs clinical sign-off (D-18) |
| Diet engine targets pipeline (doc 04 steps 1–10, 12) | **done** | 87 tests, 99.7 % stmt / 96.0 % branch |
| Engine steps 11, 13, 14 (pool, fill, alternates) | **unblocked, not built** | the 281-food DB now exists (D-40/D-41), so D-10's block is stale; remaining gaps are 12 unseeded rule-pack tags + no prep-time/may_contain schema — see D-134 |
| Rule-pack loader + `EngineService` | **done** | 15 tests |
| Flutter deps | **done** | 144 packages resolve; `flutter analyze` clean |
| Flutter auth + session | **done** | OTP sign-in works on a physical device (D-28) |
| Flutter onboarding flow | **done** | submits to `POST /profile/onboarding`; 70 tests pass |
| Flutter shell / all four tabs | **done** | Home/Plan/Progress/You all live on the design system (D-45, D-46, D-53); tab changes turn like a cube with the walker travelling across them (D-56); You frames him through a hole in the page (D-59); one shell-owned walker, no hand-offs (D-60); onboarding not migrated. Home restyled to the new reference mock (D-141, D-142); Progress is the mock's dashboard — section chips, calorie/macro/weight/consistency cards — fed by a 14-day diary fan-out the backend still owes a summary endpoint for (D-143, doc 21) |
| Backend boilerplate fork | **done** | postgres + migrations + seeds run |
| Backend phone OTP (E1 auth half) | **done, delivery stubbed** | 6 tests; fixed dev code, in-memory store (D-29) |
| Backend `POST /profile/onboarding` | **done** | profile + versioned health_profile + consents; gates re-run server-side (D-31) |
| Backend `GET /profile`, `PATCH /profile`, `PATCH /profile/health` | **done** | merge-forward + re-gate on every edit (D-33, D-34) |
| Backend `POST /plans/generate`, `GET /plans/current` | **done, targets only** | meals `[]` until E2; gates + idempotency verified (D-36, D-37) |
| Backend `POST /measurements`, `GET /measurements/:kind` | **done** | delta rule + MA7; docs/16 "−30 kg" defect prevented (D-38) |
| Food DB schema + CSV import | **done, 281 foods + 1268 aliases** | `food` + `household_measure`; import/verify/search live (D-40, D-41) |
| Backend `POST /logs/food`, `GET /logs/day` | **done** | nutrition copied per entry; 48 h lock (D-42) |
| Flutter Home tab + food logging | **done** | `+` food tab searches, logs by katori; Home shows totals vs targets (D-43) as the walking-man hero with macro rings (D-55), uncarded on the page (D-57) |
| Flutter Progress tab | **done** | weight log + trend, four states, docs/05 §6 tone enforced by test (D-39) |
| Flutter `+` sheet weight tab | **done** | reuses the Progress tab's `LogWeightForm` — one suspect rule, one history. Redesigned to the reference: kg/lb (stored as kg), ruler over the server's 20–300 range, `recorded_at` (D-127) |
| Home dashboard v2 | **done** | reference layout on the walker's stage; logging streak inside docs/05 §6's letter; premium pill server-gated (D-138) |
| Fibre eaten (API + app) | **done** | `food_log.fibreG` migration, copied at log time, in day totals + targets; Plan shows eaten/target (D-136) |
| Flutter billing client | **read-only** | entitlements + prices wired; premium surfaces server-gated; checkout is the D-134 S3 epic |
| Flutter daily tracking | **done** | Home browses back 90 days (`GET /logs/day?date=`); Progress charts steps, water and calories burned as a week of bars (D-128) |
| Flutter You tab | **done** | real profile, four states, edit sheets, profile photo (D-34, D-35) |
| Admin panel | **not started** | AdminJS per doc 20 §3 — contradicts ADR-006 |
| git | **done** | 15 commits on `main` |

## Checks — run these instead of trusting this table

| Command | Expect |
|---|---|
| `cd api && npm run test:engine` | 90 passed |
| `cd api && npx jest` | 99 passed, 9 suites |
| `cd api && npx ts-node scripts/validate-rule-packs.ts` | `ok v1.0.0` |
| `cd api/packages/diet-engine && npx jest --coverage` | ≥95 % stmt/func, ≥90 % branch |
| `flutter analyze lib test` | No issues found |
| `flutter test` | 396 passed (re-run 2026-09-01, D-128) |
| `cd api && docker compose up -d postgres` | container running — required by everything below |
| `cd api && npx env-cmd -f .env npm run migration:run` | migrations execute (D-24: env-cmd is not optional) |
| `cd api && npx env-cmd -f .env npm run seed:run:relational` | roles + statuses exist (D-30: unseeded ⇒ every user insert 500s) |

## Open decisions blocking others

1. **GV-03 fat: 22 % or 25 %?** (D-12) — blocks trusting the muscle-gain path.
2. **GV-04 protein taper** (D-13) — needs a clinician. Blocks the older-diabetic path.
3. **GV-06 needs new inputs** (D-14) — the vector is arithmetically unsound.
4. **Clinical sign-off on the rule pack** (D-18) — blocks launch, not development.
5. **`tinymce` XSS** (D-17) — blocks shipping an admin panel.
6. **ADR-006 is stale** — doc 20 §3 says revise it; `docs/07-adr-log.md` still says Flutter web.

## Scope note — Phase 0 mostly does not apply (D-19)

Doc 17's Phase 0 assumes the existing 20-screen prototype. This is a clean rewrite, so
`docs/15-ux-audit-screenshots.md` is a **"never build these"** checklist, not a backlog. Tasks 0.3,
0.4, 0.7 and 0.8 evaporate; 0.2, 0.5, 0.6 and 0.9 fold into E1/E2/E4/E8. ~2–3 weeks removed.

## Four tracks (D-20)

```
Track A  E2 food DB — starts first, never stops     critical path, mostly data entry
Track B  boilerplate fork → E1 → E3 rest → E5 → E7  backend
Track C  shell → onboarding → plan view → E4        Flutter
Track D  AdminJS on food tables                     unblocks Track A
```

## Next, in order

1. **E2 food data entry — first 281 foods are IN** (`docs/templates/foods-seed.csv`, verified and
   searchable). Remaining: breadth (regional dishes, brands), and a clinician or dietitian review of
   the numbers — they are `source: manual`, not IFCT-traceable, which docs/03 asks for.
2. Resolve D-12/D-13/D-14 so the golden vectors are trustworthy. D-13 needs a clinician.
3. AdminJS on `foods` / `recipes` / `household_measures` (~1 day, doc 20 §3).
4. Start the household-measures table by hand, in parallel with everything.
5. The `docs/14` §2 shell (Flutter) runs alongside.

## Epic status (doc 17)

| Epic | Est | State |
|---|---|---|
| E1 identity & onboarding | 8–10 d | ~85 % — OTP, session, onboarding, profile read/edit done; `GET /auth/me` and measurements pending |
| **E2 food database** | 10–14 d | schema + import tooling done; **data entry is the remaining work** |
| E3 engine & plans | 8–10 d | ~85 % (engine, generate/persist, meal split + Plan tab done; alternates, override, actual meals pending) |
| E4 logging & progress | 8–10 d | ~35 % — measurements + Progress tab done; food logging blocked on E2 |
| E5 billing | 10–12 d | ~25 % — entitlements + tiers + price matrix + enforcement done; no payment provider (D-54) |
| E6 coach surface | 10–12 d | not started |
| E7 partner | 8–10 d | not started |
| E8 admin | 10–12 d | not started |
| E9 compliance | 6–8 d | not started |
| E10 hardening | 6–8 d | not started |
