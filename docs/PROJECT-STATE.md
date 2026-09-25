# Project state

**Purpose: answer "where are we?" without reading the repo.** Overwrite this file when state
changes — it is a snapshot, not a history. History lives in `DECISIONS.md`.

Last verified: 2026-09-18 (E8 close) · verified by running the commands in the Checks table, not by reading code.

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
| Engine steps 11, 13 (pool, fill) | **built, wired and converging** | The fill is a bounded beam search (D-231), not the greedy of docs/04 §7 — that could not satisfy energy, protein, fat and sodium at once and left a day 17–48 % short. A real 30-year-old's day now lands at 2,708 kcal against 2,711, protein 80/80, fibre 51/38, sodium 1,866/2,000, verified against the live 281-food table. Meals fill in order, each carrying the last one's residual. Fibre, saturated fat and docs/04 §7's per-meal protein floor are consulted for the first time; added sugar is priced below its cap, not only over it; four ingredient rows (atta, maida, besan, raw suji) are tagged `attr:ingredient` and never served. `test/real-pool.spec.ts` builds four different people from the real CSV. OPEN: what a plan may CONTAIN — a day can hit every number and still read as vada pav and sugarcane juice. Needs composition rules and a dietitian |
| Engine step 14 (alternates) | **blocked on a pack diff** | the 281-food DB now exists (D-40/D-41), so D-10's block is stale; remaining gaps are 12 unseeded rule-pack tags + no prep-time/may_contain schema — see D-134 |
| Rule-pack loader + `EngineService` | **done** | 15 tests |
| Flutter deps | **done** | 144 packages resolve; `flutter analyze` clean |
| Flutter auth + session | **done** | OTP sign-in works on a physical device (D-28) |
| Flutter onboarding flow | **done** | submits to `POST /profile/onboarding`; 70 tests pass |
| Flutter shell / all four tabs | **done** | Home/Plan/Progress/You all live on the design system (D-45, D-46, D-53); tab changes turn like a cube with the walker travelling across them (D-56); You frames him through a hole in the page (D-59); one shell-owned walker, no hand-offs (D-60); onboarding not migrated. Home restyled to the new reference mock (D-141, D-142); Progress is the mock's dashboard — section chips, calorie/macro/weight/consistency cards — fed by a 14-day diary fan-out the backend still owes a summary endpoint for (D-143, doc 21) |
| Backend boilerplate fork | **done** | postgres + migrations + seeds run |
| Backend phone OTP (E1 auth half) | **done, delivery stubbed** | 6 tests; fixed dev code, in-memory store (D-29) |
| Backend `POST /profile/onboarding` | **done** | profile + versioned health_profile + consents; gates re-run server-side (D-31) |
| Backend `GET /auth/me` | **done** | docs/09 §3 aggregate: user, roles, entitlements, active plan summary; 6 tests (D-163) |
| Onboarding eligibility (FR-1.2, FR-1.5) | **done** | under-18 and BMI<18.5 goal weight refused before any write; DB CHECK on age verified live; 7 tests (D-163) |
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
| Flutter billing client | **buys** | entitlements + prices wired, premium surfaces server-gated, and the paywall starts a real checkout against Cashfree (D-196). Stub builds say so on the button rather than implying a payment; the Cashfree SDK lands with the first sandbox credentials |
| Home-screen widget | **built, three sizes on both platforms** | One dark-green design on iOS and Android, small/medium/large each laid out for its space; Android's "+" logs a glass in the background (it never did before), iOS's opens the app to add it; taps route (D-210, D-219) |
| Health platform sync | **checked on iPhone + Watch and on real Health Connect (emulator); release items open** | Steps, distance and active calories from Health Connect / HealthKit, today on load and resume plus a 30-day backfill on connect; `POST /measurements/bulk`, `GET /logs/windows`; "Health data" screen on the You tab. De-duplication, active-only energy and manual-wins confirmed on real stores (D-217). Open: a real Samsung walk (Samsung Health not set up on the test phone, and it never writes active calories), the privacy policy page (`eatzify.app/privacy` does not resolve), the Play Console declaration, and HealthKit on the paid Apple team. Home offers to connect once and always shows Connect/Sync; a tap takes today's device figure over a typed one (D-218). Steps typed on the `+` sheet are stored apart as `steps_added` and sit on top of the device's count, so a sync no longer wipes them (D-220, D-221). Tracker: `docs/HEALTH-SYNC-TRACKER.md` (D-214 to D-221) |
| Reminders | **built; checked on the Android emulator, not yet on an iPhone** | Water, meal logging and end of day, scheduled on the phone a week ahead with no backend. Times come from the profile, the time zone from the phone. Opened from You → Reminders and from a bell on Home's water card. "Log a glass" works from the notification. Plan: `docs/REMINDERS-PLAN.md` (D-222) |
| Flutter daily tracking | **done** | Home browses back 90 days (`GET /logs/day?date=`); Progress charts steps, water and calories burned as a week of bars (D-128) |
| Flutter You tab | **done** | real profile, four states, edit sheets, profile photo (D-34, D-35). Reads back every onboarding answer, not the ten it used to (D-176); every fact is a tinted glyph row and the last in a card drops its divider (D-190); the account's own phone number has its own section, unmasked and not editable without an OTP flow that does not exist (D-193); "Invite friends" hands the OS share sheet a link rather than reading the address book (D-192) |
| Admin panel | **signed-in, and reaches everything E8 built** | AdminJS at `/admin-panel`; the Next.js dashboard in `admin/` now has a login, an httpOnly session, middleware and a working logout (D-234) — before that it signed in as one service account from `.env.local`, so anyone who opened the URL had every admin power and the audit log named nobody. Ten screens: partner applications, clients, find someone, support, food review, send a message, live metrics, audit log, rule packs, security (D-232). The five placeholder destinations from the template are gone. Backend: `audit_log`, metrics, application queue, verify/reject, audit search, user search, segment notifications, food review, tickets, rule-pack activation and TOTP (D-227 … D-230) |
| git | **done** | 15 commits on `main` |

## Checks — run these instead of trusting this table

| Command | Expect |
|---|---|
| `cd api && npm run test:engine` | 114 passed |
| `cd api && npx jest` | 579 passed, 48 suites (D-233) |
| `cd api/packages/diet-engine && npx jest` | 153 passed, 6 suites — includes `real-pool.spec.ts` against the real CSV (D-231) |
| `cd api/packages/diet-engine && npx jest` | 114 passed, 5 suites |
| `cd api && npx ts-node scripts/validate-rule-packs.ts` | `ok v1.0.0` |
| `cd api/packages/diet-engine && npx jest --coverage` | ≥95 % stmt/func, ≥90 % branch |
| `flutter analyze lib test` | no errors or warnings; 16 infos (import order, redundant args) predate D-214 |
| `flutter test` | 792 passed (re-run 2026-09-18, D-233) |
| `flutter build ios --debug` · `flutter build apk --debug` | both build, iOS signed with HealthKit (D-217) — the Android project defines no flavors, so `--flavor dev` fails |
| `cd api && docker compose up -d postgres` | container running — required by everything below |
| `cd api && npx env-cmd -f .env npm run migration:run` | 19 migrations execute (D-24: env-cmd is not optional) |
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

0. **E3's last mile — engineering DONE, nutrition sign-off pending (D-235).** All 281 rows carry
   `group:` tags; the fill prices composition when a pack carries the block; step 14 (alternates)
   is built and traced. Both blocks are optional and absent from v1.0.0 — goldens unchanged. What
   remains is ONLY the reviewed pack diff: the proposed v1.1.0 in D-235 needs a dietitian's
   `reviewed_by` (and their answers to the questions listed there) before it enters
   `config/rule-packs/`.
1. **E2 food data entry — first 281 foods are IN** (`docs/templates/foods-seed.csv`, verified and
   searchable). Remaining: breadth (regional dishes, brands), and a clinician or dietitian review of
   the numbers — they are `source: manual`, not IFCT-traceable, which docs/03 asks for.
2. Resolve D-12/D-13/D-14 so the golden vectors are trustworthy. D-13 needs a clinician.
3. AdminJS on `foods` / `recipes` / `household_measures` (~1 day, doc 20 §3).
4. Start the household-measures table by hand, in parallel with everything.
5. The `docs/14` §2 shell (Flutter) runs alongside.
6. Reminders on the phone (D-222):
   - **Built:** water, meal logging and end of day.
   - **Next:**
     - try them on a real iPhone;
     - decide on the weekly weigh-in (needs a clinical yes);
     - the rest of `docs/REMINDERS-PLAN.md` §2.
7. **The money paths are still unverified against a real gateway.** `api/.env` points at PRODUCTION
   Cashfree, so buy / upgrade / refund have been exercised by unit test only, and two real unpaid
   orders exist from before this was noticed. Switch the dev environment to sandbox or the stub, then
   verify them (D-194, D-224).
8. ~~E8's routes have no admin screen~~ — closed by D-232: the dashboard reaches tickets, the
   food review queue, user search, rule-pack activation and TOTP enrolment.

9. **Offers + revenue (D-236) are live behind the dev stack** — coupon checkout, TOTP-gated admin
   offers, and the revenue rollup. Untested against a real gateway for the same reason as item 7:
   the money paths still need the sandbox pass.

## Epic status (doc 17)

| Epic | Est | State |
|---|---|---|
| E1 identity & onboarding | 8–10 d | **done** — OTP, session, onboarding, profile read/edit, measurements; `GET /auth/me` returns the docs/09 §3 aggregate; under-18 and unreachable-goal-weight refused at input, with a DB CHECK behind the age floor (D-163) |
| **E2 food database** | 10–14 d | schema + import tooling done; **data entry is the remaining work** |
| E3 engine & plans | 8–10 d | ~93 % — engine, generate/persist, meal split, Plan tab; steps 11 + 13 built, wired and now CONVERGING (D-231): the beam search lands a real day inside every pack tolerance against the live food table, and `assertFilledDayCoherent` no longer throws. Pending: meal composition (the plan hits its numbers on street food — a nutrition decision, D-165/D-231), step 14 alternates (blocked on a rule-pack diff), coach override, revisions, and the diabetic carb-cap conflict the pack contains (D-231) |
| E4 logging & progress | 8–10 d | ~75 % — food, water and weight logs, diary-day, 90-day browsing, MA7 trend, windowed change, the Progress dashboard all done; Health Connect / HealthKit steps, distance and active calories built but not yet checked on a device (D-214 — the earlier "Health Connect steps done" was wrong: Android read nothing) (D-38, D-42, D-43, D-86, D-128, D-158). The "blocked on E2" note was stale from before the 281 foods landed. Pending: adherence, which exists nowhere in the codebase |
| E5 billing | 10–12 d | ~85 % — entitlements, tiers, price matrix and enforcement done; Cashfree wired with an order table, signed webhooks and a stub mode that boot refuses in production (D-194). Verified end to end: FREE → checkout → simulate → PRO. Trials, cancel, proration upgrades, refunds with commission reversal and the daily renewal sweep with its T-7/T-3/trial-48h notices are all built and tested, with "Your plan" under You (D-223, D-224). Pending: Play Billing (deferred), the Cashfree SDK for a live gateway, and live verification of the money paths — the dev `.env` points at production Cashfree, so those were exercised by unit test only. The app-side paywall is wired (D-196): it starts a checkout, names the price on the button, and shows "opening soon" only when the server says it cannot take money |
| E6 coach surface | 10–12 d | ~98 % — docs/10 §1's eight roles seeded, `SessionRole` maps them to the two shells rule 1 allows, `RootGate` routes by it, `CoachShell` skeleton with its four tabs, reached from the You tab rather than replacing the client shell — a coach still tracks their own food (D-168, D-174). Coach signup built to docs/12 §6: agreement grants level 1, documents submit for review, verification left to an admin (D-169). Consent grants built and enforced — scopes capped by coach level, expiry binding on read, revoke pausing rather than deleting — with the "Who can see my data" screen (D-173). Invite flow built and tested — asking creates no access, the level cap applies at the ask, expiry binds on read, and creating an invite never reveals whether the number has an account (D-175). What the applicant says they do is recorded on the application, revisable until submission and frozen once a reviewer holds it — onboarding's answer to the same question is routing only and still never stored (D-191). `GET /coach/clients` and `GET /coach/clients/:id` return the roster and one filtered client — the intersection of what the client granted and what the coach's level reaches, re-checked at read time so a demotion bites without rewriting grants, with `read_health` audit rows where a health field actually leaves (D-195). The app's Clients tab now shows the people who accepted above the invites still waiting, and each row opens a detail page that renders exactly what the grant allowed — absent fields draw no row, and a near-empty page says why (D-199). Check-ins and alerts are built (D-225): a weekly review per client, generated as the queue is read, sorted missed-first, with docs/02 FR-5.3's four signals above it. Chat is built (D-226): REST for the conversation, socket.io for live delivery, the `chat` grant re-checked on every call — the coach's Messages tab and the client's "Message my coach" are the same screens. The client-side invite inbox was already built (D-199 era). The coach's own You tab shows where they stand as a partner and the way back to their own account (D-174); earnings and the referral code stay on the Clients tab (D-200). Nothing in E6's scope is a placeholder any more |
| E7 partner | 8–10 d | ~45 % — attribution (first-touch, locked by the schema), referral codes, a versioned commission rate table and an append-only ledger that reverses rather than edits; `GET /coach/earnings` and `GET /coach/referral` are live and the app renders both (D-201, D-202). ⚠ The seeded rates are docs/12 §2's recommendation and have nobody's sign-off. Pending: payouts, TDS and GST handling (docs/12 §5 defers both to a CA), and the `?ref=` capture at signup |
| E8 admin | 10–12 d | ~90 % — `src/admin/` carries `audit_log`, the metrics overview, the partner application queue, verify/reject and audit search; AdminJS serves `/admin-panel` and a Next.js dashboard in `admin/` reads the REST API (D-180 … D-183). The review queue names the applicant and masks their phone, with the full number behind an audited reveal that now also needs a TOTP code. `POST /admin/users/search` (masked, audited when it filters by condition), `POST /admin/notifications` (docs/13 §5's condition rule enforced) and the food review queue — draft → reviewed → published → retired with names against each step — are built (D-227). Support tickets are built on both sides: the client's Help screen under You and `GET /admin/tickets` + reply / resolve / close, with docs/03 §5's states and its seven-day reopen window (D-228). Rule-pack activation is built — super_admin only, two people, append-only history, and the database rather than `RULE_PACK_VERSION` deciding what is live after a restart — behind an RFC 6238 second factor checked against the RFC's own test vectors (D-229). `is_demo` is a column on `user` and the metrics rollup excludes it (D-230). Pending: an admin UI for the newer routes, and `GET /admin/users/{id}` |
| E9 compliance | 6–8 d | ~45 % — the data-subject rights are built and tested (D-233): itemised consents that can be withdrawn (and a withdrawal that actually stops plan generation), `POST /privacy/export` with its 24-hour link, `POST /privacy/delete` with docs/13 §9's seven-day cooling-off, the 48-hour warning and a nightly sweep that erases — a real delete of the health rows plus a tombstone, per docs/13 §6 — and the app's "Privacy & data" screen under You. Admin 2FA landed with D-229. Pending: the retention sweep for the rest of docs/13 §6's table, the grievance form and named officer, the nominee field, versioned public policy pages, and §7's column-level encryption |
| E10 hardening | 6–8 d | not started |
