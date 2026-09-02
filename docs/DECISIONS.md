# Decision log

Append-only. Newest last. One entry per decision that would be expensive to rediscover.

**Read this before re-deriving anything.** If a decision here is wrong, add a superseding entry —
never edit an old one. `docs/07-adr-log.md` holds *product/architecture* ADRs; this file holds
build-and-tooling decisions plus every place the specs disagree with each other.

Format: `## D-nn — title` · **When** · **Decision** · **Why** · **Reverses if**

---

## D-01 — Monorepo, Flutter at the root, backend in `api/`
**When** 2026-08-24 · **Decision** One repo. Flutter stays at the repo root; the NestJS backend is
`api/`. `docs/` is shared at the root.
**Why** `docs/PLACEMENT.md` offers two-repo or monorepo. The Flutter project already existed at the
root, so `apps/mobile/` would have meant moving `android/`, `ios/`, `.idea/`, `.metadata` and the
`.iml` files for no gain. Monorepo also makes every `docs/NN-*.md` reference inside the backend rules
and skills resolve unchanged.
**Reverses if** the release trains genuinely conflict — Play staged rollout vs several API deploys a
week is the friction `PLACEMENT.md` warns about.

## D-02 — One `.claude/`, at the repo root only
**When** 2026-08-24 · **Decision** No `api/.claude/`. Backend allow/deny/hooks/env merged into the
root `.claude/settings.json`; backend scoping done by path-scoped rules plus `api/CLAUDE.md`.
**Why** `settings.json` permissions are enforced only at the project root. A nested copy would look
authoritative and silently do nothing — worse than not having it.
**Reverses if** Claude Code starts honouring nested settings files.

## D-03 — Backend rule globs re-scoped, not copied
**When** 2026-08-24 · **Decision** Backend rules shipped with globs like `src/**/*.controller.ts`;
all rewritten to `api/src/**`. `testing.md` collided with the Flutter rule and became
`api-testing.md`.
**Why** Under a monorepo the original globs match nothing, so the rules would never fire.

## D-04 — `docs/` is a full copy, not a submodule
**When** 2026-08-24 · **Decision** All 21 docs live in `docs/`.
**Why** No git repo exists yet and there is no `eatzify-docs` remote to submodule.
**Reverses if** a second repo appears — `PLACEMENT.md` is right that duplicated docs diverge inside a
month. Switch to a submodule the same day the API repo splits out.

## D-05 — `intl` bumped from doc 20 §7's `^0.19.0` to `^0.20.2`
**When** 2026-08-24 · **Decision** Pin `^0.20.2`.
**Why** `flutter pub get` fails outright: the SDK's `flutter_localizations` hard-pins `intl 0.20.2`.
Doc 20 §7 says re-check every version at install time; this is one that moved.

## D-06 — `flutter_localizations` added, though doc 20 §7 omits it
**When** 2026-08-24 · **Decision** Added, plus `generate: true`, `l10n.yaml`, and `app_en.arb` /
`app_hi.arb`.
**Why** `CLAUDE.md` rules 4 and 5 (never show a raw enum, no hardcoded strings) are unimplementable
without it. Doc 20 §7 lists `intl` but not the SDK package l10n actually needs.

## D-07 — `very_good_analysis` replaces `flutter_lints`; `sort_pub_dependencies` disabled
**When** 2026-08-24 · **Decision** Swapped the `analysis_options.yaml` include. Disabled the
alphabetical-dependency lint.
**Why** Doc 20 §7 specifies `very_good_analysis` as the stricter set. Its A–Z lint would destroy doc
20's concern-grouped manifest, and the grouping carries the reason for each pin.

## D-08 — `@sentry/nestjs` bumped from doc 20 §8's `^8` to `^9`
**When** 2026-08-24 · **Decision** Pin `^9`.
**Why** `npm install` failed with ERESOLVE: `@sentry/nestjs@8` peers `@nestjs/common` 8–10 only,
against §8's pinned `^11`. `^9` is the first line supporting Nest 11.

## D-09 — Diet engine is server-only for now
**When** 2026-08-24 · **Decision** `api/packages/diet-engine` is a plain workspace package, not a
publishable private npm package.
**Why** Matches `CLAUDE.md` rule 2 — the server decides, the app renders. Simplest thing that works.
**Reverses if** offline plan preview is wanted (ADR-004's reasoning leans on it). The package is
already free of Node-specific APIs, so extraction is work but not a rewrite.

## D-10 — Engine pipeline steps 11, 13, 14 deliberately not implemented
**When** 2026-08-24 · **Decision** `distributeMeals` emits per-slot targets. Candidate pool, greedy
fill and alternates are absent.
**Why** They need the food database. Doc 20 §1 and §6 record that the Indian home-cooked table with
household measures does not exist and has to be built by hand. Doc 04 §2: a partial plan is worse
than no plan — and fake food is worse than both.

## D-11 — `api/src/main.ts` and `app.module.ts` not hand-written
**When** 2026-08-24 · **Decision** Only `src/modules/engine/` exists, and it is framework-free.
**Why** Doc 20 §2 and §10 step 1 say the app skeleton comes from a pruned fork of
`brocoders/nestjs-boilerplate`. Hand-writing it would contradict the doc and duplicate work.

## D-12 — SPEC CONFLICT: GV-03 contradicts itself on fat
**When** 2026-08-24 · **Decision** Implemented doc 04 §5 (muscle_gain fat = 22 % E → 67 g, carbs
422 g). Test records the divergence and passes.
**Why** Doc 16 GV-03 states "fat 76 g (22 % E)" — but 76 g is 684 kcal = **25.0 %** of 2739, and its
own carb figure of 402 g only balances at 25 %. The vector's grams are a 25 % calculation wearing a
22 % label. **Open: someone must pick 22 or 25.**

## D-13 — SPEC GAP: GV-04 uses an undocumented protein rule
**When** 2026-08-24 · **Decision** Implemented the written fat_loss rate of 1.8 g/kg ABW → 129 g. No
`renal_protein_caution` emitted.
**Why** Doc 16 GV-04 expects 101 g at "1.4 g/kg, reduced for age+condition". Neither `1.4` nor that
trigger appears anywhere in doc 04 §5 or doc 05 §2 — grepped. The only renal taper defined is `ckd`,
or age **>** 60 **with** diabetes **and** hypertension; GV-04's user is 60, diabetic, not
hypertensive. **Open: needs the clinically-qualified reviewer doc 05 mandates, then a pack entry —
not a code edit.**

## D-14 — SPEC ERROR: GV-06's BMR is wrong and the vector self-inverts
**When** 2026-08-24 · **Decision** Implemented Mifflin correctly: bmr 979, tdee 1175, target 1200.
**Why** Doc 16 GV-06 states bmr 1071 / tdee 1285. Mifflin for female 44 kg / 148 cm / 45 y is
440 + 925 − 225 − 161 = **979**, so tdee = 1175. Corrected, TDEE falls *below* the 1200 female floor,
so the floor binds and the answer is 1200 — the exact value the vector asserts against. It cannot
demonstrate its own "BMI check precedes the floor" point with correct inputs. **Open: GV-06 needs
new inputs where TDEE lands above 1200.**

## D-15 — Added sugar takes the tighter of two bounds
**When** 2026-08-24 · **Decision** `min(5 % of energy, 25 g)` when a sugar-restricted condition is
declared — not a replacement of one rule by the other.
**Why** Doc 04 §5 reads as either. At GV-02's 1517 kcal, 5 % = 19 g, tighter than the 25 g absolute.
Doc 04 §6 says later rules tighten and never loosen, so `min` is the only reading consistent with it.
The vectors' "added_sugar ≤25 g" is an upper bound that 19 g satisfies.

## D-16 — Snack protein floor applies only below 10 % of target
**When** 2026-08-24 · **Decision** The 4-meal `snack` slot (15 % of target) gets the full ≥20 g floor.
Only the 5_6 pattern's mid-morning (8 %) and bedtime (5 %) slots get the 10 g exception.
**Why** Doc 04 §7: "except snacks < 10 % of target". 15 % is not < 10 %. My first test asserted 10 g
and was wrong; the implementation was right.

## D-17 — `tinymce` XSS left unfixed, pending a decision
**When** 2026-08-24 · **Decision** Not fixed. 1 high-severity, 5 XSS CVEs, reached via AdminJS.
**Why** A fix exists but likely means an AdminJS major bump. Running `npm audit fix --force` on the
admin panel unattended is worse than a recorded known issue. **Open: your call.**

## D-18 — Rule pack v1.0.0 is transcribed, not clinically approved
**When** 2026-08-24 · **Decision** `config/rule-packs/v1.0.0.yaml` carries a `REVIEW STATUS` header
saying so.
**Why** Doc 05 requires a named reviewer with a clinical qualification, recorded in the ADR log,
before these constants serve a real user. Tooling transcription is not that. **Open: blocking for
launch, not for development.**

## D-19 — Clean rewrite; the existing prototype is not imported
**When** 2026-08-24 · **Decision** The 20-screen prototype stays where it is. This repo is a fresh
build. `docs/15-ux-audit-screenshots.md` becomes a **"never build these"** checklist, not a defect
backlog.
**Why** Doc 17's Phase 0 (2–3 weeks) is entirely "fix what is wrong in the current build" — but that
build is not in this repo. Importing it would inherit the four navigation shells, the hamburger menu
and the architecture doc 14 was written to replace, then pay to remove them. Building the one shell
correctly the first time is strictly cheaper.
**Effect** Phase 0 tasks 0.3, 0.4, 0.7, 0.8 evaporate. 0.1 is ~60 % done (D-10). 0.2, 0.5, 0.6, 0.9
survive but fold into E1/E2/E4/E8 rather than standing alone. **~2–3 weeks removed from the schedule.**
**Reverses if** something in the prototype turns out to be worth more than rewriting it — in which
case port that piece specifically, never the whole tree.

## D-20 — Build order: boilerplate fork + AdminJS before anything else
**When** 2026-08-24 · **Decision** First code: prune a `brocoders/nestjs-boilerplate` fork into
`api/`, then point AdminJS at the food tables. E1 onboarding proceeds in parallel.
**Why** Doc 17's sequencing advice: E2 (food database) is the critical path and the only task that
cannot be compressed with better code. Every other epic is blocked on it being good enough. The
household-measures table is manual data entry — it cannot start without a CRUD screen, and AdminJS
gives one in about a day (doc 20 §3) versus a week hand-built.
**Reverses if** the boilerplate turns out to fight us more than it helps — the prune list is the
early warning.

## D-21 — supersedes D-14: GV-06's outputs were right, its inputs were mistranscribed
**When** 2026-08-24 · **Decision** Keep GV-06's stated outputs. Replace its inputs with
**female, 45 y, 155 cm, 48.8 kg, sedentary**. Landed as `GV-06b` in `golden.spec.ts`; the original
GV-06 test stays as the record of the defect.
**Why** D-14 concluded the vector was arithmetically unsound. That was half right. Searching for the
profile that yields doc 16's stated `bmr 1071 · tdee 1285 · raw target 1028` finds an exact match at
45 y / 155 cm / 48.8 kg — the **age matches the doc**, so only height and weight were mistyped
(148 cm / 44.0 kg). BMI comes out 20.3 against the doc's stated 20.1, consistent with rounding.

With the corrected inputs the vector demonstrates exactly what it claims: BMI 20.3 suppresses the
deficit, target becomes TDEE 1285, and since 1285 > the 1200 female floor the floor never binds —
which is only true if the BMI check ran first. Applying the floor to the raw 1028 target would have
given 1200.
**Status** Resolved, pending your confirmation that 155 cm / 48.8 kg is the intended profile. D-12 and
D-13 remain open; D-13 still needs the clinical reviewer.

## D-22 — Cloudflare R2 for object storage, not AWS S3
**When** 2026-08-24 · **Decision** Object storage is Cloudflare R2. The boilerplate's `s3` and
`s3-presigned` uploaders are kept unchanged — R2 is S3-compatible, so the AWS SDK talks to it once
given an endpoint.
**Why** R2 charges **no egress fee**. Eatzify serves progress photos, coach documents and food images
to phones in India; on S3 that egress is the line item that grows with users rather than with
revenue. `docs/06-architecture.md` §1 already specifies "S3-compatible", so no ADR is contradicted.
`docs/18-ops-runbook.md` §9 budgets ₹300–800/month for "object storage + egress" — R2 puts that at
the storage-only end of the range.
**What changed** `S3_ENDPOINT` and `S3_FORCE_PATH_STYLE` added to `FileConfig` and threaded through
all four `S3Client` construction sites (`s3/files.module.ts`, `s3-presigned/files.module.ts`,
`s3-presigned/files.service.ts`, `domain/file.ts`). Region defaults to `auto`, which is what R2
documents. `AWS_S3_REGION` became optional in the validator, since R2 has no regions.
**Reverses if** you need an AWS-only feature (S3 Object Lock, Glacier tiering). Set `S3_ENDPOINT`
empty and a real region, and the same code speaks to S3.
**Watch** R2 presigned URLs must stay the only way health imagery is served — `docs/13` §6. Do not
attach a public custom domain to the bucket holding progress photos.

## D-23 — Safety copy is quoted verbatim from docs/05 §7, and Hindi needs sign-off
**When** 2026-08-24 · **Decision** Every safety string in the app is the exact text from
`docs/05-clinical-safety-guardrails.md` §7 — under-18 block, blocking gate, clinician gate, safety
clamp, disclaimer, eating-disorder routing. The disclaimer now also appears in the onboarding footer.
**Why** §7 says "use verbatim; do not paraphrase". The first onboarding build shipped my own wording
on the gate screen, which is exactly the drift that section exists to prevent — the phrasing *is* the
safety feature. `CLAUDE.md` rule 7 says the same thing for server-supplied text.
**Open** The Hindi strings are a translation, and a translation is by definition not verbatim. They
are provisional and need the qualified reviewer `docs/05` §8 requires before any Hindi launch. The
eating-disorder helpline link is deliberately inert: §7 flags that the India-appropriate resource
must be verified with a clinician before shipping.

## D-24 — docs/05 §4 screening is its own step with three distinct outcomes
**When** 2026-08-24 · **Decision** Added a screening step after conditions, asking §4's three
questions. It routes to one of three end states: `eatingDisorderSupport`, `blocked`,
`clinicianRequired` — evaluated in that severity order.
**Why** The condition multi-select cannot catch these. `docs/03` §2 has no `eating_disorder` or
`type_1_diabetes` value, because §4 collects them by question instead. Conflating the three outcomes
would put eating-disorder support behind a coach-unlock, or tell a pregnant user that a coach can
unlock a plan for her. They are not interchangeable, so they are separate enum values with separate
copy and separate tests.
**Note** The support screen cannot be backed out of into the calorie form, and carries no enabled
action — `docs/05` §6: a safety message is never behind a paywall or a "continue anyway".

## D-25 — Session state is one enum at the root, not guards on every route
**When** 2026-08-24 · **Decision** `SessionController` owns the session and exposes an `AuthStatus`
of `restoring | signedOut | onboardingRequired | signedIn`. `RootGate` switches on it exhaustively.
**Why** `docs/14` §3 asks for `AuthGuard` / `OnboardingGuard` declared on `GetPage`. With four states
and three destinations, one exhaustive switch at the root gives the same guarantee with less
machinery — and unlike a per-route guard it cannot be forgotten when someone adds a page. Revisit
when `EntitlementGuard` and `RoleGuard` arrive with E5 and E6; those are genuinely per-route.
**Notes** `restoring` is a real state, not an inferred null — the splash shows while the keychain is
read. `onboardingRequired` comes from the server (`docs/09` §3); the app never infers it from
whether a profile happens to be cached.

## D-26 — Refresh rotates both tokens, and a rejected refresh signs the user out
**When** 2026-08-24 · **Decision** The dio interceptor retries a 401 exactly once. On success both
access AND refresh tokens are replaced and persisted; on failure the session is cleared locally
*without* calling `/auth/logout`.
**Why** `docs/09` §3: refresh rotates, and reuse of a rotated token revokes the whole family. So a
rejected refresh means the token is already dead — calling logout with it is pointless and tells an
attacker the endpoint responds. Retrying more than once is how an app hammers the API and burns a
user's data allowance in the background.
**Notes** `signOut` clears local state even when the server call fails — a user who taps sign out on
a plane must not stay signed in. `Session.toString()` omits both tokens (`docs/13`: no credential in
a log line).

## D-27 — Sign-in cannot complete yet, and the app says so
**When** 2026-08-24 · **Decision** The full phone-OTP client is built against `docs/09` §3 and calls
real endpoints. Those endpoints do not exist: `api/src/auth` is the boilerplate's *email* flow, and
`docs/20` §2 pruned social sign-in because phone OTP is primary auth in India.
**Why** Building the client now means only the datasource changes when E1 lands. The failure surfaces
as the server's own message rather than a spinner.
**Open** `BACKEND_DOMAIN` is `http://localhost:3001` — a phone cannot reach the host's localhost, so
a LAN address or tunnel is needed before sign-in works on a device. `deviceId` is a placeholder
string; a stable per-install id belongs there so the server can name sessions in a security screen.

## D-28 — Phone OTP endpoints are live; supersedes D-27
**When** 2026-08-24 · **Decision** `POST /auth/otp/request` and `POST /auth/otp/verify` exist in
`api/src/auth` and return the `docs/09` §3 shape (`{ access, refresh, user, onboarding_required }`).
Sign-in works end to end on a physical device. D-27's "cannot complete yet" no longer holds.
**Why** The client was already built against the contract, so only the endpoints were missing.
**Notes** Three separate bugs had to be cleared, each hiding the next, and all three will recur on a
new machine: (1) `localhost` is unreachable from a physical phone — the base URL is now a LAN IP,
overridable with `--dart-define=API_BASE_URL=…`; (2) iOS blocks cleartext HTTP, so
`ios/Runner/Info.plist` carries `NSAllowsLocalNetworking`; (3) the Flutter base URL omitted the `/v1`
segment that `docs/09` §11 requires. D-27's `deviceId` placeholder is still open — `otp/verify`
accepts `device` and currently ignores it.

## D-29 — OTP delivery is a dev stub, and the store is in-memory
**When** 2026-08-24 · **Decision** No SMS provider is wired. Every number accepts the fixed
`OTP_DEV_CODE` (default `000000`). Codes and per-number rate limits live in two `Map`s inside
`OtpService`.
**Why** MSG91 with DLT-registered templates (`docs/09` §3) needs an account, credentials and per-SMS
cost, none of which should block the login screen from working. `deliver()` is the only thing that
changes when a real provider lands; no caller moves.
**Reverses if** the API runs more than one process. The maps are per-process, so both the codes and
the 3/hour/number limit silently stop working behind a load balancer — move to Redis at that point.
**Notes** The `docs/09` §3 rules that are NOT stubbed: the OTP is never logged, `otp/request` always
returns 204 so it never reveals whether a number exists, 5-minute TTL, 5-attempt lockout. Six unit
tests in `api/test/otp.service.spec.ts` cover expiry, lockout, replay and the rate-limit window.

## D-30 — `seed:run:relational` is a required setup step, not an optional one
**When** 2026-08-24 · **Decision** A fresh database must be seeded before any user can be created:
`cd api && npx env-cmd -f .env npm run seed:run:relational`.
**Why** `user.roleId` and `user.statusId` are FKs to the `role` and `status` lookup tables. Unseeded,
those tables are empty and *every* user insert fails with a foreign-key violation surfacing as a bare
500 — the error names a constraint, not the missing seed, so it costs an hour to diagnose. This is
not specific to OTP; the email flow would have failed identically.
**Notes** `migration:run` must go through `env-cmd` for the same reason (D-24): `data-source.ts`
reads `process.env` directly, so the TypeORM CLI sees an undefined driver without it.

## D-31 — Onboarding persists; the gates are re-run server-side and the server wins
**When** 2026-08-24 · **Decision** `POST /profile/onboarding` (docs/09 §4) writes `profile`, a new
`health_profile` version and `consent` rows in one transaction, and returns
`{ user_id, health_profile_version, gates[] }`. `api/src/profile/screening.ts` re-runs every
docs/05 §3 gate. If it returns a gate the client did not catch, the app routes to the gate screen
instead of continuing.
**Why** The flow previously collected everything and then called a *local* `markOnboardingComplete()`
— every answer was discarded, and a reinstall meant redoing onboarding forever. The client screening
in `validate_onboarding.dart` stays, but as a courtesy: an app build is not a trustworthy
enforcement point for a clinical gate.
**Notes** `onboarding_required` is now a real check (`hasCompletedOnboarding`), replacing the
`!user.firstName` placeholder from D-28. Users who hit a gate are still stored — docs/05 §3 blocks
plan *generation*, not the account, and discarding their answers would only force them through the
same questions to reach the same refusal. `health_profile` is append-only because a plan must be
traceable to the exact profile version it came from. 15 tests in `api/test/screening.spec.ts`;
3 widget tests cover submit, a server gate, and a failed submit.

## D-32 — The dev base URL is a hardcoded LAN IP, and it will keep breaking
**When** 2026-08-24 · **Decision** `lib/main.dart` defaults `API_BASE_URL` to a literal LAN IP,
overridable with `--dart-define=API_BASE_URL=…`.
**Why** A physical device cannot reach the host's `localhost`, and there is no tunnel yet.
**Reverses if** it costs more time than it saves. It already broke once inside a single session: the
Mac moved from `192.168.2.38` to `192.168.2.18` when the network changed, and the app went dead with
a connectivity error that looks exactly like a server being down. The fix is a tunnel with a stable
hostname (and `NSAllowsArbitraryLoads` instead of `NSAllowsLocalNetworking`), or reading the IP at
build time. Anyone hitting "No connection" on device should check `ipconfig getifaddr en0` first.

## D-33 — A health-profile PATCH merges forward and re-runs the gates
**When** 2026-08-24 · **Decision** `PATCH /profile/health` writes a new `health_profile` version.
An omitted field carries forward from the current version; an explicit `[]` clears. Every docs/05 §3
gate is re-evaluated on the merged result, so a gate can both appear and disappear as a user edits.
**Why** Two failure modes, both silent. A replace-semantics PATCH would drop a declared condition
just because the client sent only `allergies` — the condition disappears and the gate with it. And a
PATCH that skipped re-evaluation would let a user add `ckd` after onboarding and keep generating
plans, which is precisely what docs/05 §3 exists to stop.
**Notes** `PATCH` before onboarding is a 422 `ONBOARDING_REQUIRED`, not a silent create — there is no
version to merge against. Verified against postgres: three versions retained, nothing overwritten.
6 tests in `api/test/profile.service.spec.ts`.

## D-34 — Onboarding answers are editable, in two halves, and an edit re-gates
**When** 2026-08-24 · **Decision** `PATCH /profile` (goal, activity, diet, meals, lifestyle, budget,
weight) and `PATCH /profile/health` (conditions, allergies), reached from two edit sheets on the You
tab. Both merge forward. A `PATCH /profile` that moves age, height or weight re-runs the docs/05 §3
gates and writes a new health-profile version; a change to a non-clinical field does not.
**Why** Nothing was editable after onboarding — the only way to change an answer was to be a new
user. And anthropometrics feed the BMI and age gates, so an edit that skipped re-evaluation would
let someone onboard at a safe weight, edit down to a BMI of 15, and keep receiving plans. Verified:
44 kg at 172 cm produces `bmi_below_16`, and restoring the weight clears it.
**Notes** The client sends ONLY changed keys. Sending the whole object would overwrite fields the
user never touched with values read at page load — a lost update whenever anything else changed in
between. Age, height and sex at birth are deliberately not editable in the sheet: each moves a gate
and none is a routine correction, so they belong in a support flow. 7 controller tests, 5 service
tests. **Open:** weight lives in two places now — the profile and, once `POST /measurements` exists
(docs/09 §4), the measurement log. Decide which is authoritative before building E4.

## D-35 — Profile photo: reuses the boilerplate files module, no new endpoints
**When** 2026-08-24 · **Decision** Optional profile photo on the You tab. Upload is
`POST /files/upload` then `PATCH /auth/me` with the returned file id — both already existed in the
fork. `GET /profile` gained a `photo_url` key so the tab still needs one request. The image is
downscaled to 800 px and compressed to 85 % quality on device before upload.
**Why** Requested; not in any spec — `docs/14` has no screen for it and the PRD does not list it.
Building endpoints would have duplicated a files module the boilerplate already ships, wired to a
`photo` relation `UserEntity` already had.
**Notes** docs/13 applies: a face photo is personal data. It is optional, removable from the same
sheet that sets it, and never logged. On-device downscaling matters on Indian data plans — an
unresized 12 MP shot is a ~5 MB upload. The iOS usage strings were updated: the camera string said
only "scan a food barcode", which Apple rejects once the camera is also used for a profile photo.
**Open** `FILE_DRIVER` is `local`, so photos land on the API server's disk and will not survive a
redeploy or scale past one instance. Switch to S3 before any real user uploads one. No size limit is
enforced server-side — the client caps dimensions, but a crafted request is unbounded.

## D-36 — `POST /plans/generate` ships targets-only, and a blocking gate persists nothing
**When** 2026-08-25 · **Decision** `POST /plans/generate` (docs/09 §4.2) reads the stored profile and
latest `health_profile`, runs the engine, and persists the plan with `rulePackVersion` and
`healthProfileVersion` on the row. `meals` is `[]` until E2 lands. `GET /plans/current` returns the
most recent plan.
**Why** The engine's targets pipeline is done and a stored health profile now exists to feed it, so
targets are shippable while meals wait on the food database (engine steps 11/13/14 are blocked on
E2). Storing both versions with the plan is what makes a plan reproducible byte-for-byte months
later (docs/16 GV-09) — both inputs move underneath it otherwise.
**Notes** A blocking gate throws 422 `PLAN_GATE_BLOCKED` and writes NOTHING. docs/04 §2 step 6: a
partial plan is worse than no plan, and a persisted row with null targets would look like a plan to
every later query. `Idempotency-Key` is a partial-unique column — a retried request returns its
original plan rather than billing a second generation. Verified live: BMI 15.9 blocks on
`bmi_critical`; BMI 17.9 with fat_loss clamps to 1990 kcal and emits `safety_clamp_applied`.
**Open** The Plan tab UI is deliberately NOT built. A screen showing a calorie number with no food
attached runs close to what docs/05 §6 pushes against — decide the framing first.

## D-37 — Gate and warning copy lives in one file, quoted verbatim from docs/05 §7
**When** 2026-08-25 · **Decision** `api/src/plans/plan-copy.ts` maps every engine `GateCode` and
`WarningCode` to approved user-facing text. Engine warnings with no approved string are DROPPED, not
shown. The nine "we clamped your target" warnings collapse to one `safety_clamp_applied` message.
**Why** docs/05 §7 says "use verbatim; do not paraphrase" — the wording is the safety feature, and
CLAUDE.md rule 7 makes this the only text the app shows. One file means one place to audit, and the
tests make an edit to that copy deliberate rather than silent.
**Notes** Three gates route to DIFFERENT messages and must never be merged: a blocking condition
gets the referral, an eating-disorder disclosure gets the support message (docs/05 §4 is explicit it
must never be answered with a coach-unlock), age gets the under-18 message. An unknown gate code
falls back to the referral string rather than leaking the code to a user. 8 tests.

## D-38 — Measurements own weight; the delta rule and MA7 are what prevent the old "−30.0 kg"
**When** 2026-08-25 · **Decision** `POST /measurements` and `GET /measurements/:kind` per docs/09 §4,
backed by docs/08's exact table: `UNIQUE (userId, kind, diaryDate)`, `isSuspect`, diary-day dating.
The Progress tab renders the history behind all four view states.
**Why** docs/08 says the unique constraint plus `isSuspect` are *together* what stop the old build's
"−30.0 kg change" readout — one reading per day, and implausible jumps flagged and excluded from the
trend. A second weigh-in the same day corrects the first rather than adding a point.
**Notes** Suspect = change per elapsed day above a per-kind limit (3 kg/day for weight), so 4 kg over
three weeks is normal while the same change overnight is not. A FIRST reading is never suspect —
there is no delta to judge it by. The change readout comes from a moving average with suspect points
removed, never min/max (docs/16). Verified live: a 30 kg overnight jump flags, and the change reads
−0.15 rather than −30. Null change means "no trend yet" and is NOT rendered as 0.0.
**Open** D-34's question is now answerable but not yet resolved: `profile.weightKg` and the weight
measurement series both exist. Measurements should become authoritative and the profile field derived
from the latest reading — until then a user editing weight in two places gets two answers.

## D-39 — The Progress tab is deliberately plain
**When** 2026-08-25 · **Decision** A line, a latest value, one neutral sentence. No streak, no
badge, no colour-coded zone, no marker on a day without an entry.
**Why** docs/05 §6 forbids leaderboards and streaks on weight and forbids red "Missed" markers — and
a weight chart is exactly where those get added without anyone deciding to. A gain is stated in the
same voice as a loss.
**Notes** Tests assert the absence of "Obese", "Missed", "Failed" and "streak" from a rendered gain,
and that one reading reports "log a few more days" rather than a fabricated 0.0 kg change. Those
assertions are the point of the file — they fail loudly if someone adds a motivational flourish.

## D-40 — Food data enters by CSV import, not AdminJS
**When** 2026-08-25 · **Decision** `POST /foods/import` (admin, multipart CSV) with a spreadsheet
template at `docs/templates/foods-template.csv`. `POST /foods/verify` makes rows live. AdminJS is NOT
built, contradicting docs/20 §3.
**Why** Two reasons. AdminJS 7 is pure ESM (`"type": "module"`) against this CommonJS NestJS app —
the dynamic-import workaround fights `nest build`, costing days. And D-17's `tinymce` XSS already
blocks shipping an admin panel publicly. Separately, a spreadsheet is simply the better tool for the
actual job: 200–300 rows are faster to type in Sheets than in any web form, and the sheet can be
handed to someone else so data entry runs parallel to development.
**Reverses if** browsing and editing existing foods becomes the common operation rather than bulk
entry. CSV is good at loading, poor at "find this one food and fix its sodium".
**Notes** An import is all-or-nothing: any invalid row rejects the whole file with row numbers. A
partially-imported food database is worse than an empty one — you cannot tell which half is real.
Re-importing the same `name` UPDATES rather than duplicating, so the sheet stays the source of truth.
13 validation tests.

## D-41 — Imported foods are invisible until explicitly verified
**When** 2026-08-25 · **Decision** Rows arrive `isVerified = false` and are excluded from search and
plan generation. `POST /foods/verify` flips them.
**Why** Import and publish are different acts. A half-typed food that reaches a user's plan is a
clinical problem, not a data-quality one — and the calorie cross-check (±25 % against 4/4/9) catches
a mistyped column but cannot catch a plausible-but-wrong number.
**Notes** The importer's hard checks: tag vocabulary closed to `gi:` / `attr:` / `meal:` / `cuisine:`
because the rule pack matches those exact strings (a typo silently drops a food from a medical
constraint); allergens closed to the docs/03 §2 set because that list drives exclusion, so an
unlisted peanut reaches a peanut-allergic user; macros ≤ 100 g per 100 g portion; `source` required
per docs/03, since a number nobody can attribute cannot be corrected later.

## D-42 — A diary entry stores its own nutrition, not a join to `food`
**When** 2026-08-25 · **Decision** `food_log` copies `kcal`/`proteinG`/`carbG`/`fatG` onto the row at
log time (docs/08 §food_logs). `foodId` is kept for provenance, never for arithmetic at read time.
**Why** Food data gets corrected — that is the whole point of an editable food database. If the
diary joined live, fixing a food's sodium next month would silently rewrite what somebody ate last
week, and every historical total with it. A diary is a record of what happened.
**Notes** The client sends `{slot, food_id, measure, measure_count}` and never multiplies anything —
CLAUDE.md rule 2, and it keeps one implementation of the per-100 g scaling. A measure the food does
not define is refused rather than defaulting to 100 g, which would log a quantity nobody chose.
Entries are editable for 48 h then locked (docs/08); deleting a locked entry returns `LOG_LOCKED`.

## D-43 — Home shows "no plan yet" rather than a comparison against zero
**When** 2026-08-25 · **Decision** `GET /logs/day` returns `targets: null` when no plan exists, and
the Home tab renders "348 kcal logged" instead of "348 of 0 kcal". Macro bars are hidden entirely
rather than drawn against nothing.
**Why** A target of zero is a fabricated fact, and every bar against it reads as catastrophic
failure. Same reasoning as D-38's null trend: absent data is not zero data.
**Notes** A day with no entries is `Ready`, not `Empty` — the targets and the "nothing logged yet"
line are both real content, and an Empty state would hide the plan the user is trying to follow.
docs/05 §6 tone is enforced by test: going over target renders no "Over", "Exceeded" or "Failed",
and the macro bar clamps rather than colouring differently.

## D-44 — Foods carry a search-alias list
**When** 2026-08-25 · **Decision** `food.aliases` (text[], GIN-indexed) holds what people actually
type — `chapati`/`phulka` for roti, `maggi` for instant noodles, `golgappa` for pani puri, `dahi`
for curd. `GET /foods?q=` matches name, Hindi name and aliases; entries are lower-cased at import.
**Why** A food nobody can find is a food nobody logs, and an unlogged meal is a hole in the diary
rather than a neutral absence — it silently understates intake and corrupts every total built on it.
Canonical names are for the database; aliases are for the person holding the phone.
**Notes** 1268 aliases across 281 foods, ~4.5 each. Verified live: `chapati` → Roti, `maggi` →
Instant noodles, `golgappa` → Pani puri, `बादाम` → Almond.
**Open** No synonym ranking — `aloo` returns 7 results in alphabetical order, not by likelihood.
docs/09 §5 asks for "synonym-aware" search; this is the synonym half, not the ranking half.

## D-45 — A design system, and the four things refused from the reference design
**When** 2026-08-25 · **Decision** `docs/DESIGN-SYSTEM.md` plus `AppCard`, `StatTile` and
`SectionHeader` in `core/widgets/`. Home is rebuilt on them as the reference implementation. Added
`accentBright` (dark surfaces only) and `outlineStrong` tokens.
**Why** Five screens were each deciding their own padding, radius and emphasis. The reference design
supplied a visual direction worth adopting; a system is what stops that direction drifting one
screen at a time.
**Notes** Contrast was measured, not assumed: every dark-mode text pair clears 4.5:1, and
`accentBright` exists because `accent` at 6.0:1 was thin for a headline figure. `darkOutline` is
1.4:1 and is documented as decoration-only, with `darkOutlineStrong` for borders that carry meaning.
`StatTile` deliberately takes no colour parameter — docs/05 §6 means a macro bar can never go red
for "over".
**Refused from the reference, each against an existing rule:** the streak flame and challenge banner
(docs/05 §6), a fifth Workout tab (CLAUDE.md rule 1 — needs an ADR), the cooking community feed
(not in docs/02, and a social graph is a docs/13 question), and "calories burned" (needs E4).
**Open** Only Home is rebuilt. Progress, You and onboarding still use ad-hoc layout and should be
migrated before the system counts as adopted. Dark mode is still not switched on by default.

## D-46 — Circular gauge and macro rings, and why they carry no colour state
**When** 2026-08-25 · **Decision** `ProgressRing` and `CalorieGauge` in `core/widgets/`. Home shows
the day's calories as a large arc with three macro rings beneath. Progress and You are migrated onto
`AppCard`/`SectionHeader`. `themeMode` is now `ThemeMode.dark`.
**Why** The reference designs lead with a circular gauge, and it reads better than a bar for a
day's total. Dark mode was built but never selected — `themeMode` was unset, so the app followed the
phone's system setting and rendered light, which is why it looked nothing like the references.
**Notes** Neither ring takes a colour: a ring that turns red at 101 % is a failure marker on a
number, which docs/05 §6 forbids. `progress: null` draws an empty track rather than a full or zero
ring — absent data is not zero data (same rule as D-38 and D-43), and there is a test for it.
**Open** Onboarding and the login/gate screens are still ad-hoc. `ref_pro/` is GPL-3.0: its layout
informed direction, its code is not copied, and that must stay true.

## D-47 — The gauge counts down, and the diary groups by meal
**When** 2026-08-25 · **Decision** With a target the headline number is what is **left**; past the
target it is the **excess**, labelled "kcal over". Without a target it is what was logged. Diary
entries group under meal headings in day order, each heading carrying that meal's total, and slots
with nothing in them are omitted.
**Why** "kcal left" is the number a person acts on; "kcal logged" is a number they already know. And
a diary is read as "what did I have at lunch", not as a chronological stream.
**Notes** "over" is a statement of fact, the same neutral treatment weight gain gets on Progress
(D-39) — tests assert no "Exceeded", "Failed", "Too much" or "Missed" appears at 2000 against a
1859 target. Empty slots are omitted rather than shown greyed: an empty "Bedtime" heading every day
is noise, and docs/05 §6 means it must never read as a gap the user failed to fill.

## D-48 — A ring's track is a dimmed fill, and no target means no ring
**When** 2026-08-25 · **Decision** `ProgressRing` draws its track as the fill colour at 32 % alpha,
and draws nothing at all when `progress` is null.
**Why** The track was `surfaceContainerHighest`, which after D-46's contrast fix became the same
colour as the emphasised card it sat on — **1.00:1, invisible on screen while every test passed**.
Presence tests check that a widget exists, not that it can be seen; the bug was found from a
screenshot. An empty ring also reads as "you have achieved nothing" when the truth is "nothing to
measure against yet", and it left a large hole on the card.
**Notes** Two tests now assert the ring is absent without a target and present with one.

## D-49 — UX audit against the ui-ux-pro-max checklist; two real defects found
**When** 2026-08-25 · **Decision** Audited the app against the skill's priority-ordered checklist.
Fixed: missing accessibility labels on the two icon-only portion buttons, and a **200 % font-scale
overflow on Home**. Added `AppSizes` tokens and three font-scale regression tests.
**Why** The overflow is a CLAUDE.md rule 12 violation that nothing would have caught: `CalorieGauge`
was a fixed 200 px ring, so at 200 % text scale its inner column overflowed by 136 px. The gauge now
scales with `MediaQuery.textScalerOf`, capped at 1.6x so it cannot swallow the screen.
**Notes** The skill's `--design-system` output was largely NOT adopted: it returned an "App Store
Style Landing" pattern (a marketing-page pattern, not an app screen) and a cyan `#0891B2` palette
that conflicts with the measured dark-green tokens from D-45. Generic recommendations do not
override contrast work done against this product's own constraints. What was taken: the
priority-ordered audit checklist, icon-label discipline, and size tokenisation.
**Open** Reduced-motion is unhandled (`prefers-reduced-motion` has no equivalent check in the app),
though there is almost no animation yet. Onboarding and login are still off the design system.

## D-50 — Dashboard layout, animation budget, and an honest "burned"
**When** 2026-08-25 · **Decision** Home is a dashboard: calorie gauge centre with **supplied** and
**burned** either side, and protein/carbs/fat as animated bars beneath. `AppMotion` tokens (150 ms /
250 ms, ease-out) sit alongside the spacing tokens.
**Why** Requested, and it matches the reference apps. The animation budget is deliberate: the
guidance is 1–2 animated elements per view, so the ring sweep and the three bars animate and
nothing else. Bars stagger 40 ms apart, inside the 30–50 ms band.
**Notes** **"burned" renders an em dash, not a zero.** Activity tracking is E4 and does not exist;
a 0 would read as "you burned nothing today" rather than "we are not measuring this", and a
caption says so in words. Same rule as D-43 and D-48 — absent data is not zero data.
`AppMotion.enabled()` checks `MediaQuery.disableAnimations`, and a test asserts the bars land on
their final values with motion disabled rather than freezing partway.
**Notes** Side stats and bars are hidden entirely without a plan: an empty bar reads as failure,
and "supplied" would repeat the number the gauge already shows a few pixels away.

## D-51 — Supersedes D-48's "no ring": the layout stays, the copy carries the meaning
**When** 2026-08-25 · **Decision** Without a plan the gauge ring and the three macro bars are still
drawn, unfilled, with `supplied` and `burned` alongside. "No plan yet" and a "Create my plan" button
sit inside the same card.
**Why** D-48 removed the ring entirely to avoid an empty ring reading as "you achieved nothing".
That over-corrected: it left a hole where the screen's centrepiece belongs, and a user with no plan
— which is every user until they press the button — saw a Home tab that looked broken rather than
one that looked new. The fix for ambiguous emptiness is words, not deletion.
**Notes** The rule the earlier decisions were protecting still holds: nothing invents a number. The
bars read "62 g" with no "/ 0", the gauge says "kcal logged" rather than "kcal left", and `burned`
is an em dash with a caption explaining that activity tracking is not set up. What changed is that
absence is now shown as an unfilled control plus an explanation, not as a missing control.

## D-52 — Light mode measured and fixed; the app follows the phone again
**When** 2026-08-25 · **Decision** Light tokens re-measured and three changed: background
`#F7F9F8 → #E6EDEA`, surfaceAlt `#EDF2F0 → #F3F7F5`, outline `#D3DEDA → #B9C7C2`. Ring tracks and
bar backgrounds take a heavier alpha in light (0.45 / 0.30) than dark (0.32 / 0.20). `themeMode` is
removed so the default — follow the phone — applies.
**Why** Light mode had never been looked at. A white card on `#F7F9F8` was **1.06:1**, so with flat
design and no shadow every card dissolved into the page. The ring track was 1.85:1 against its card,
the same class of bug D-48 fixed in dark. Text was fine throughout; the failures were all boundaries.
**Notes** After the change: `muted` 4.72:1 on background, 5.61:1 on a card, figures 11.6:1 — all
pass. Card-vs-background sits at 1.19:1, which is conventional for light UI and is carried by the
border rather than by fill. Two render tests now exercise light mode, one of them at 200 % font
scale, because a theme only ever viewed in one mode is a theme with untested colours.
**Open** docs/14 §5 still expects a user-facing theme switch on a settings screen that does not
exist yet.

## D-53 — The Plan tab shows the meal split, which is what resolves D-36's open question
**When** 2026-08-25 · **Decision** `GET /plans/current` now returns `meal_targets` — the rule pack's
per-slot split with kcal and macros already applied. The Plan tab renders one card per meal, the
day's total once above them, any docs/05 §7 warnings verbatim, and a regenerate action.
**Why** D-36 left the tab unbuilt because a lone daily calorie figure with no food attached is close
to the framing docs/05 §6 pushes against. A per-meal split is not that: "about 558 kcal at
breakfast" is guidance a person can act on, and it is useful before the food database can fill in
actual dishes.
**Notes** The split is applied server-side (CLAUDE.md rule 2) and rounded once there, so the app
never decides how to round somebody's protein. Meals themselves stay empty until E2 — the cards
show targets, not dishes. All four tabs now show live data.

## D-54 — E5 foundation: entitlements are server-resolved, and two docs/11 prices were wrong
**When** 2026-08-25 · **Decision** `subscription` table, `tiers.ts` holding tier entitlements and
the price matrix, `GET /billing/entitlements`, `GET /billing/prices`, and `plan.regenerate_per_day`
enforced on `POST /plans/generate`.
**Why** Entitlements are what every later billing feature reads, and they need no payment
credentials to build — so this is the part of E5 that can ship before a Razorpay account exists.
**Notes** Entitlements resolve server-side always (CLAUDE.md rule 3); the client renders what it is
told. An expired or cancelled subscription resolves to FREE, not to nothing — free is a real tier.
A period end in the past means lapsed even if no webhook has said so, because something that
expires with the clock cannot be trusted to a status field. Gate-blocked attempts persist nothing
and so never cost a user their daily allowance. docs/11 §1's rule holds: nothing in the entitlement
table gates a gate, a warning, or a piece of docs/05 copy.
**⚠️ Two prices differ from docs/11 §2 and need sign-off.** That table breaks the monotonic-ladder
rule stated three lines below it:
  - BASIC 12M 2,199 → **2,099**. At 2,199 it was ₹183/month against 9M's ₹178 — the longer
    commitment was worse value per month, the exact defect docs/11 §2 warns about.
  - PRO 1M 549 → **649**. docs/11 suggests ₹549 monthly, but PRO 3M is ₹1,799 (₹600/month), so the
    monthly plan undercut the quarterly one and nobody would buy 3M.
  Nine tests in `api/test/tiers.spec.ts` fail if either ladder inverts again.
**Open** No payment provider. Razorpay and RevenueCat are in `pubspec.yaml` but nothing is wired —
that needs accounts and keys before purchase, webhooks or revenue reporting can exist.

## D-55 — Home's centrepiece is the walking man over three macro rings
**When** 2026-08-27 · **Decision** The Home accent card is now the walker — a 38-frame PNG walk
cycle played by `core/widgets/frame_sequence.dart` — standing on three floor rings
(`core/widgets/macro_rings.dart`) that fill with protein, carbs and fat, outer to inner, with the
day's headline and figures beside him. The calorie gauge and the macro bars leave Home.
`CalorieGauge`/`GaugeSideStat` stay in `core/widgets` unused for now; `MacroBar` still serves Plan.
**Why** Product asked for the dashboard from the `walking_animation` prototype. Its steps, sleep and
"daily goal %" did not survive the rules: no activity or sleep source exists (D-50), sleep is in no
spec, and a composite goal score would be computed client-side (rule 2). What survived is the look,
bound to the data Home already has — the D-47 headline (left / over / logged), supplied, burned as
an em dash, and the three macros as both figures and rings.
**Notes** He walks `AppMotion.walkCycles` (6 × 1.27 s) when today's numbers arrive, then rests on his
standing frame — motion that stops, not a spinner — and replays on every reload because the Ready
subtree is rebuilt. Reduced motion shows one static frame and the rings land at once; both are
tested. Rings keep one colour (D-46) and a dimmed-fill track (D-48). Above 1.3× text scale, or under
320 px, the hero stacks art over figures so a four-digit headline never clips (rule 12; the 200 %
test covers it). First `assets/` entry in the repo: 38 palette PNGs cropped to the figure's
bounding box, 492 KB, listed in `pubspec.yaml`. A finite walk is also what lets `pumpAndSettle`
return in the 20 Home tests — a looping character would hang the suite. `dart format lib test`
reformatted about thirty untouched files, whitespace only: the tree had drifted from the formatter.
**Open** "burned —" sits beside a man who is visibly walking; until E4 exists that reads as a
contradiction. The ring order is explained by a caption (`homeRingsLegend`); if that proves
invisible in use, colour-differentiated rings need a tokens decision first.

## D-56 — The walker travels between tabs; the pages turn like faces of a cube
**When** 2026-08-28 · **Decision** A tab change is animated, not cut. The outgoing page swings away
on the edge it is leaving by and the incoming one swings in from the opposite edge
(`core/widgets/cube_transition.dart`), while a second walker
(`presentation/shell/walking_man.dart`) walks between per-tab anchors over the top. He is invisible
on Home and fades in as you leave it, so he reads as stepping out of the D-55 hero card rather than
duplicating the walker already standing on its rings. `NavController` stays the source of truth:
`ClientShell` watches `selected` and animates to whatever it says, so a tab change from anywhere
animates identically.
**Why** Product asked for the `walking_animation` prototype's dashboard motion — the man who slides
and grows as you move between screens. The prototype gets it from a three-page `PageView`; that is
not available here, because a `PageView` builds the pages it scrolls past and every one of ours
fires a request on build, so swiping Home → You would have called the Plan and Progress endpoints on
the way. Driving one `AnimationController` and rendering only the two tabs either side of the turn
gives the same motion with no page built that the user did not ask for. Const page widgets keep the
element alive across the ~25 rebuilds of a turn, which is what stops each frame from re-running a
page's controller.
**Notes** Rejected: replacing the shell with the prototype's three screens (hard rule 1, and it
costs the Plan tab and the `+` sheet), and the prototype's steps / sleep / "daily goal %" figures,
which have no data source here (D-50, rule 2) — the same reasoning that shaped D-55. Anchors are
fractions of the body, not pixels, so 200 % font scale and a tablet both place him correctly; the
walk is keyed on the destination so it replays per tap and still stops (`AppMotion.walkCycles`),
which is also what lets `pumpAndSettle` return. `IgnorePointer` means he can never eat a tap meant
for the content he stands in front of. Reduced motion sets the turn's duration to zero: the tab
still changes, it just does not travel, and `FrameSequence` already holds one still frame. 11 tests
in `test/shell_walker_test.dart`.
**Open** He crosses whatever the tab is showing. On the dense tabs — Progress's chart, Plan's meal
list — his anchors keep him to a corner, but there is no collision awareness; if a tab grows a
bottom-anchored control, that anchor needs revisiting.

## D-57 — Home's hero is the screen, not a card on it
**When** 2026-08-28 · **Decision** The accent `AppCard` around the Home hero is gone. The walker,
his rings, the headline and the figures sit directly on the page background; the "create my plan"
button and its error line come with them. Entry rows keep their cards, and `AppCard(accent: true)`
stays in `core/widgets` — nothing else uses it today.
**Why** The border made the day's summary read as one widget among several rather than as the
screen. The `walking_animation` prototype stands the walker on the page itself, which is the look
product asked for; a rounded rectangle around him is the one thing that stopped it reading that way.
**Notes** The hero gained ~32 pt of width (the card's own padding), which is why the side-by-side
layout still clears `AppSizes.heroBreakpoint` at 200 % font scale — 342 pt inside the list's
paddings on a 390 pt phone against a 300 pt threshold. The list's top padding went 0 → `sm` to keep
the headline off the subtitle now that no card separates them. One test in `home_page_test.dart`
guards against the card coming back.

## D-58 — The walker walks continuously, larger, on the reference's warm page
**When** 2026-08-28 · **Decision** Three changes to the walker, reported together because they are
one complaint: he stopped, he was small, and he sat on a page that was not the reference's.
`FrameSequence.cycles` is now nullable and both walkers pass null, so the walk never ends;
`AppSizes.heroArt` 220 → 320 and `heroRings` 150 → 190; every shell anchor grew by roughly a third;
and `AppColors.lightBackground` is the reference's `#FAF5EF`, with `lightSurfaceAlt` `#F3E6DD`,
`lightOutline` and `lightOutlineStrong` rewarmed to match.
**Why** D-55 made the walk finite on the grounds that motion should stop rather than spin. In use
that reads as the animation freezing — a figure caught mid-stride and held there is not at rest, it
is stuck, which is the opposite of what a walk cycle is for. Size and background are the same
complaint from the other side: at 220 pt on a cool green page he read as an icon pasted beside the
figures rather than as the screen's subject.
**Notes** Contrast was re-measured, not assumed: on `#FAF5EF`, muted text is 5.2:1, body 15.4:1 and
primary 11.5:1. A white card is only 1.08:1 against the page, so the edge does the separating —
which is why `lightOutline` is both warmer AND stronger than the green it replaced (1.94:1 on white,
was 1.75:1) and `lightOutlineStrong` clears the 3:1 UI-boundary rule at 3.7:1. Reduced motion is
unchanged: one still frame, and `AppMotion.enabled` is still checked first.
**Cost** A screen showing the walker can never settle, so `pumpAndSettle` times out on it. The four
suites that mount one now call `settle()` from `test/pumping.dart`, which pumps a fixed span
instead — everything finite still completes, and the assertions are unchanged. The D-55 test that
asserted he rests on his standing frame is replaced by one asserting he is still moving twelve
seconds in, well past where the old six-cycle walk ended.

## D-59 — The You tab is the reference's frame: the walker seen through a hole in the page
**When** 2026-08-28 · **Decision** The You tab opens with `ProfileFrame` — the walker drawn behind
the page's surface, which is painted as a rounded rectangle minus a circle, so only what falls
inside the circle shows. The heading, the age figure and "years old" sit top-left beside it, and the
plan's daily targets follow as four `StatTile`s under a "Daily goals" heading. The shell's
travelling walker now fades out approaching You exactly as it does approaching Home, so the tab that
frames him is never showing two of him.
**Why** Product asked for the `walking_animation` reference's third screen. The hole is the whole
point of it: a `ClipOval` would give a circular portrait, which reads as a cropped photo — the
reference frames a figure who continues behind the page, and that only works as a painted difference
path with the surface drawn over him.
**Notes** The reference's tiles are three saturated fills (orange, purple, blue) carrying steps and
sleep. Neither survived: there is no steps or sleep source (D-50), and a colour per macro is the
first step towards a red one, which docs/05 §6 forbids — so the targets are the plan's four real
numbers in the app's own tile. `AccountController` loads them through `PlanRepository.current()`
deliberately OUTSIDE its `ViewState`: the profile is this screen's subject, so a plan that is missing
or that failed to load drops the tiles and leaves the page intact rather than blanking it. No plan
says so in words instead of showing four zeroes (D-43). `IntrinsicHeight`, not
`CrossAxisAlignment.stretch`, levels each pair of tiles — a Row in a `ListView` has no height of its
own and stretch hands its children an infinite one.
**Cost** The tab is now taller than the 600 pt test surface, so its lower sections are built only
after a scroll; `test/pumping.dart` gained `scrollTo` and the affected assertions scroll first. Five
tests cover the frame, the tiles, the no-plan copy and the plan-failure path.
**Open** `ProfilePhoto` still sits under the frame as its own circle. Two circles in a column is one
too many; the photo probably belongs inside the frame, which needs a diameter on that widget and a
decision about what shows when a user has no photo.

## D-60 — One walker, owned by the shell; the tabs draw his setting, not him
**When** 2026-08-28 · **Decision** There is exactly one `FrameSequence` in `lib/`. It lives in
`WalkingMan`, never fades, and is never rebuilt. Home's hero draws the macro rings and nothing else;
`ProfileFrame` draws the panel with the hole and nothing else; both leave the figure to the shell,
whose Home and You anchors put him on those rings and in that circle. `WalkingMan.destination` is
gone with the key that used it, and `ProfilePhoto` moved inside the frame at
`AppSpacing.minTouchTarget` instead of sitting under it at full avatar size.
**Why** Plan→Progress looked smooth and Home→Plan and Progress→You did not, which is a complete
description of the bug: those two are the boundaries where a second walker existed. Crossing them
cross-faded the shell's traveller against the page's own figure at a different size and position, so
two men were briefly on screen — the fade could be tuned but never made right, because the two are
not the same object. One figure cannot be handed off. Keying the sequence to the destination was the
same mistake in time rather than space: it rebuilt the widget on arrival, so he broke stride at the
end of every transition.
**Notes** The double avatar was the same fault in a third place — the frame's circle and the photo
control were two portraits of one person. The circle is where a user's own walking cartoon will go
when that exists, so the photo control belongs on the panel with it, small. Cost: the walker no
longer scrolls with the rings or the frame, because he is positioned against the body rather than
inside the page. At rest — which is when a tab is looked at — he is on them; scrolled, he stays put.
Both anchors are fractions of the body, so they hold across screen sizes, but they are eyeballed
against a 390 x 844 phone and are the first thing to nudge if he sits off his rings on other
hardware.
**Open** A user-specific walking cartoon generated from their uploaded photo, shown in the frame's
circle in place of the stock walker. Not started; the photo control is placed where it will be
changed from.

## D-61 — A colour per macro, and the walker holds his ground
**When** 2026-08-28 · **Decision** Two changes taken from the reference build running side by side.
(1) The three macro rings and the You tab's goal rows are coloured per macro — protein, carbs, fat —
using the reference's own hues from `AppColors.macroProtein/macroCarb/macroFat`, and the goal rows
are filled coloured bars with white text rather than neutral tiles. This supersedes D-46's single
fill. (2) `WalkingMan.anchors` is now a tight cluster instead of four corners, so a tab change moves
the screen behind a walker who stays roughly where he is.
**Why** Product ran the prototype and asked for both by pointing at them. D-46 chose one ring colour
so that a ring could not be read as a score; the colours here are identity, not judgement — a macro
keeps its colour whether it is under target or over, which is the part docs/05 §6 actually forbids
changing, and three concentric rings in one colour cannot be told apart without counting inwards.
The anchors were the same misreading in motion: corner-to-corner made the tab change look like the
walker being flung across the screen, where the reference holds him still and slides the world.
**Notes** Contrast was measured, not eyeballed. The reference's fills fail white text — orange 3.1:1
and blue 2.4:1 — so each was darkened along its own hue and saturation until it cleared 4.5:1, and
no further: protein 4.6:1, carbs 6.0:1 (the reference purple unchanged), fat 4.6:1. One token per
macro serves both the ring and the row that names it, which is what ties the two screens together.
Calories takes the brand green: it is the day's total, not a macro, and a fourth hue would imply a
fourth ring. The goal rows have a minimum height, not a fixed one, so they wrap at 200 % rather than
clipping. `ProfileFrame`'s hole moved to follow the walker's You anchor rather than sitting in the
panel's centre — the page draws the setting, so the setting goes where the figure is.
**Open** The four anchors are eyeballed against a 390 x 844 phone: they are fractions of the body,
so they scale, but whether he stands ON the hero's rings and centred IN the profile circle has not
been checked on a device. That is two numbers per tab in one table if he sits off his mark.

## D-62 — The rings are the floor, not an indicator
**When** 2026-08-28 · **Decision** The macro rings gained their own stroke and gap tokens
(`AppSizes.ringStroke` 13, `ringGap` 7, from a shared `barHeight` of 8 and `AppSpacing.xs`), their
track opacity went 0.28 → 0.55 light / 0.5 dark, and they paint `heroRingsPainted` (270) wide inside
a `heroRings` (190) column via an `OverflowBox`. Home's headline moved from `displaySmall` to
`displayLarge`, and each macro figure's icon now wears its ring's colour.
**Why** Side by side with the reference the rings read as three grey hairlines rather than as the
floor a man is standing on — worst on a day with no plan, where only the tracks paint and 0.28 alpha
left almost nothing on screen. The stroke was inherited from `barHeight`, which is a 6–8 pt
indicator inside a tile; this is read across a whole screen at arm's length, so it needed its own
token rather than a shared one bent to fit. The width was the same mistake: a floor that stops at
the edge of its column reads as a coaster, and the reference's runs on behind the figures.
**Notes** The icons are decoration only — the value and label beside each carry the meaning, so
nothing is lost to a colour-blind reader; the ring legend stays for the same reason. The 200 % font
scale test passes unchanged with the larger headline, which is what `height: 1` on it is for.

## D-63 — Whatever must line up with the walker asks him where he is
**When** 2026-08-28 · **Decision** `WalkingMan.boundsIn(body, position)` returns his exact rect, and
his own build places him with it and nothing else. Home's macro rings moved out of the hero's
`ListView` into a `_Floor` layer under the whole tab, positioned from that rect — centred on his
feet. The hero keeps an empty `SizedBox` where he stands so the figures still sit in their column.
**Why** The rings were at his waist. Nothing was miscalculated: the rings were laid out by the list,
at the bottom of a 320 pt art box below a tab header, while the walker was placed against the body
by a fractional anchor. Two correct calculations from one set of tokens, ~160 pt apart on screen —
and no amount of nudging either number fixes that class of bug, because the next font scale or
header height breaks it again. One of them had to ask the other. It also fixes the case nobody had
tried: scrolling Home, where the rings used to walk off up the screen and leave him standing on
nothing.
**Notes** The rings do not scroll now, which is correct — the figure standing on them does not
either. They sit under the tab header layer, so they pass behind the figures the way the reference's
do, and `OverflowBox` is gone with the column that needed it. One test asserts the rings' centre is
within half a point of his feet, in both axes.
**Not a defect** "The rings do not show progress" on a day with no plan is D-43 working: no target
is not a target of zero, so a ring with no goal draws its track and no fill. The fills appear when
`POST /plans/generate` succeeds — which needs the API reachable at `API_BASE_URL`, currently a LAN
address.

---

## D-64 — Seven goals for the user, three for the engine

**When** Extending onboarding to the product's full question list (2026-08-28).
**Decision** The goal step now offers the seven options the product asked for — weight loss, weight
gain, fat loss, muscle gain, general fitness, medical/nutrition support, other — stored verbatim as
`goal_declared`. The engine's `goal` (`fat_loss | muscle_gain | maintenance`) is *derived* from it
via `GoalDeclared.engineGoal` and stays the only thing that drives calorie direction. Both are sent
and both are persisted.
**Why** docs/04's rule pack defines calorie and macro semantics for exactly three directions. Adding
"general fitness" as a fourth engine goal would mean inventing a target for it, which is the app
computing a target (CLAUDE.md rule 2) and a rule-pack change that needs clinical review. Mapping
silently and *discarding* the user's choice was the other option, and it loses the one piece of
information a coach actually wants: someone who picked "medical support" is not the same client as
someone who picked "fat loss", even when the plan maths is identical.
**Notes** `weight_gain → muscle_gain` is the weakest link in the mapping: a surplus is the only
upward direction the engine has, so a user who wants to gain weight without a muscle-gain protein
target currently gets the muscle-gain track. It is the closest honest answer, not an equivalence.
**Reverses if** the rule pack grows a lean-gain track or per-goal constants, at which point
`weight_gain` and `general_fitness` should become real `Goal` values and this mapping deleted.

## D-65 — The four new conditions are collected, not gated

**When** Same change as D-64.
**Decision** `high_cholesterol`, `fatty_liver`, `heart_problem` and `digestive_issue` were added to
the condition list. None of them is in `isBlockingGate` or in the server's `BLOCKING_CONDITIONS`, so
none of them changes whether a plan is generated. They are stored, versioned and visible to a coach.
**Why** Whether a cardiac or hepatic condition should stop plan generation is a docs/05 clinical
decision requiring a dietitian's sign-off. Guessing it in either direction is the harmful option:
gate them speculatively and a large group of users who could safely be planned for gets refused;
leave them ungated silently and nobody knows the question was never asked.
**Open** `heart_problem` is the one to classify first. A cardiac patient currently receives an
auto-generated plan on the strength of a checkbox and the three docs/05 §4 screening questions,
which do not ask about cardiac history.
**Reverses if** docs/05 is revised with a classification for these four — at which point the values
move into the gate lists and the engine's `cond:*_ok` tags need matching thresholds.

## D-66 — The macro rings are circles inside the walker's own column

**When** Reported as "the rings are overlapping" with a screenshot (2026-08-28).
**Decision** Three changes, all reversing parts of D-62. The rings are drawn as circles
(`Rect.fromCircle`, equal inset in both axes) instead of squashed floor ellipses — `ringSquash` is
deleted. Their painted diameter is `heroRings` (190) instead of `heroRingsPainted` (270), so they
stay inside the column they share with the walker. And the hero's captions — the "burned" note and
the ring legend — moved from full-width under the row into the left figures column.
**Why** The overlap had two causes and neither was the rings crossing each other. Painted at 270
against a 190 column, the ellipse ran left across the figures and the caption text, so the legend
explaining the rings was printed on top of them. And squashed to 0.36 the three rings crowd together
at the left and right extremes while staying apart at the top and bottom — at the sides they read as
touching even though the concentric spacing is uniform. A circle has one spacing everywhere.
**Notes** The rings are still painted in the fixed `_Floor` layer at the walker's feet, so a long
diary still scrolls behind them; that is D-63 working and is not the reported bug. What is fixed is
that nothing collides at rest. `shell_walker_test`'s D-63 assertion (rings centred on his feet) is
unchanged and still passes; `macro_rings_geometry_test` now pins the circles and the gaps.
**Reverses if** the floor-perspective reading returns — at which point the squash belongs in the
painter as a canvas transform, not as unequal axis insets, so the ring spacing stays uniform.

## D-67 — The floor look is a tilt, not a squash

**When** "Now it is not looking good" against the walking_animation reference screenshot
(2026-08-28), pointing at `lib/widget/rings.dart` in the reference project.
**Decision** Read the reference and copied its actual mechanism. It paints **true circles** — square
rects of 140, 165 and 190 — and lays them on the floor with a 3D transform,
`Matrix4..setEntry(3, 2, 0.0011)..rotateX(-1.28)`. `MacroRings` now does the same: circles, tilted.
Stroke and gap dropped to the reference's 10 and 2.5, and the three per-macro dimmed tracks
collapsed to one faint neutral (reversing D-48 and D-62's track).
**Why** Three separate faults, and "the rings overlap" was only the first.
1. *The overlap.* Squashing the rects left the stroke at full 13 pt while the gaps between rings
   compressed to 7 pt, so at the near and far edges of the ellipse three strokes met. A rotation
   compresses strokes and gaps by exactly the same amount, so the spacing holds all the way round.
   D-66 fixed this by dropping the ellipse; it also dropped the floor, which was the wrong half to
   keep.
2. *The band.* At stroke 13 / gap 7 the radii stepped by 20 and the innermost ring landed at 0.55 of
   the outer — three hoops around a hole rather than one band. The reference steps by 12.5, which
   puts it at 0.72.
3. *The colour.* Three dimmed tracks plus three filled arcs is six saturated rings competing. The
   reference has one quiet `#EFEAE6` track and lets the three fills carry all the colour, which is
   most of what "clean" was describing.
**Notes** Verified by rendering `MacroRings` to a golden and looking at it rather than reasoning
about the maths — the first attempt at the tilt was measurably wrong and reading the image is what
caught it. `macro_rings_geometry_test` pins the band ratio and the non-overlap; `shell_walker_test`'s
D-63 assertion is untouched.
**Reverses if** nothing foreseeable. If the tilt is ever tuned, tune it against a render, not by
picking a number.

## D-68 — The You frame goes in front of the walker

**When** "The card will be over the walking animation, also only half of the body will be visible"
(2026-08-28).
**Decision** `ProfileFrame` moved out of the account page's `ListView` and into a new
`ProfileFrameLayer`, rendered by the shell as the layer ABOVE `WalkingMan`. The page keeps a
`SizedBox(height: AppSizes.profileFrame)` where it used to be. The layer anchors itself to the
walker via `WalkingMan.boundsIn` — its hole lands on his chest — and fades in over the last of the
walk to You so it does not snap in on a tab change.
**Why** D-59 already said "the panel covers the rest of him", but the shell painted the walker last,
so it never did: the hole was decoration he happened to stand over while his whole body drew on top
of the card, legs hanging past its bottom edge into Daily goals. Being *in front* is what makes a
hole a hole. It could not be fixed inside the account page because the walker is positioned against
the body and does not scroll — a frame laid out by a scrolling list cannot be a fixed layer above
him, which is the same constraint D-63 hit with the Home rings, resolved the same way.
**Notes** The panel decoration and the heading are wrapped in `IgnorePointer`. Drawn in front of the
page, anything hit-testable there swallows the list's scroll — the account tests caught this as a
drag that would not hit test, and it would have been a dead scroll on the real screen. The photo
button stays tappable. `account_page_test`'s harness now mirrors the shell's stack rather than
pumping the page alone, since the page no longer draws the frame.
**Unverified** How much of him shows through the hole was not confirmed on a device: the walker's
PNG frames do not load under `flutter test`, so the golden render shows the card and hole placement
but not the figure. `_holeAtHeightFraction` is the knob if he sits too high or low in the circle.

## D-69 — The cube turns vertically, and the You card turns with it

**When** "The things are coming from the bottom, it should come from top — also the card too"
(2026-08-28), from a screenshot caught mid tab-change.
**Decision** `CubeTransition` rotates about X instead of Y: a face now hinges on its top or bottom
edge, not its left or right. The shell's direction flipped with it, so going forwards the page being
left drops away through the BOTTOM and the new one arrives from the top. And the shell now reads the
face once per frame — `_face()` returns `(tab, turn)` — so the page and the `ProfileFrameLayer`
stacked over it are handed the same angle.
**Why** Two separate faults in one frame. The turn was sideways, so nothing ever entered from the
top; with the perspective applied it read as content fanning up from the bottom of the screen. And
the card, which D-68 had just moved into its own layer above the walker, was outside the turn
entirely — it sat flat and square while the page behind it rotated, which read as a sticker stuck
over the transition rather than as part of the tab.
**Notes** `_turning` wraps only while there is an angle to show: at rest the page is itself, with no
permanent Transform and Opacity, which `shell_walker_test` already pinned. `ProfileFrameLayer` lost
its own opacity fade — the cube's fade carries it now, and two fades left the panel washed out
through the middle of every change. The walker stays outside the cube: he walks between tabs rather
than turning with them (D-56).
**Reverses if** the direction should depend on travel — forwards from the top, backwards from the
bottom is what it does now; a single fixed direction would be a one-line change to `leaving`.

## D-70 — You is a full-bleed sheet with a hole, drawn over the walker

**When** "I want the things to come from the top so the walking animation gets hidden under it, just
like is happening in the lib profile section" (2026-08-28) — after two wrong attempts.
**Decision** Read `lib/screen/3.dart` and `lib/screen/home_view.dart` in the reference project and
copied the arrangement. Its `ThreeScreen` is a `HolePainter` sheet at `1.sw × 1.sh` — the FULL
screen, with one circular hole — and `home_view` renders it *after* the walking man in the stack.
So: `FramePainter` is now full-bleed and square-cornered, painted at the root of `AccountPage`, and
the shell layers the whole You page in front of the walker while every other tab stays behind him.
`ProfileFrameLayer` is deleted; `ProfileFrame` is reduced to the heading, age and photo that sit
beside the hole.
**Why** D-68 and D-69 both missed the point by treating the frame as a *card*. A 320 pt card inset
by page padding covers almost none of a full-height figure — his legs hung past its bottom edge
across the content below, which is exactly what was being reported. The reference never had a card:
it has a sheet the size of the screen, and the figure is behind the screen showing through a hole in
it. Once the sheet is full-bleed, "only half of him is visible" and "he is hidden under it" are the
same statement, and both come out of the geometry rather than needing to be arranged.
**Notes** The hole is placed from `WalkingMan.boundsIn` rather than from a fixed fraction as the
reference does — the page's Stack is at the root of a `Positioned.fill`, so its box IS the shell
body, the same coordinate space the walker answers in (D-63). The list's leading band is sized from
the hole's bottom minus the measured header height, so the tab title's font scale cannot push
content over the walker's face. `_holeAtHeightFraction` (0.3) is the knob for how far down his body
the circle sits.
**Reverses if** a second tab ever needs to be layered over him, at which point `overWalker` should
become a property of the page rather than a tab check in the shell.

## D-71 — You slides down over the walker; it does not turn

**When** "Things come from top but from under — make it come from top", with a screen recording
paused mid-transition (2026-08-28).
**Decision** The You page no longer uses `CubeTransition`. It is translated down from above the
screen — `FractionalTranslation` from `(0, -1)` to `(0, 0)`, driven by the same walk position that
moves the walker — and it sits in front of him for the whole change, not just the second half. While
You is arriving or leaving, the page behind him does not turn either.
**Why** A cube face shrinks in perspective as it turns. The walker does not: he is outside the cube
because he walks between tabs rather than turning with them (D-56). So mid-turn he stood at full
size while the sheet meant to be covering him was a shrunken trapezoid, and he poked out of every
edge of it — which reads exactly as the page arriving from underneath him. The reference has the
same instinct: it *translates* its third screen over the man (`home_view.dart`), it does not rotate
it. A full-screen sheet that translates covers whatever it passes over, at every frame of the
journey; one that rotates only covers at the end.
**Notes** Two transitions at once — one sliding, one rotating behind it — reads as neither, so the
page behind is held still for the duration. The slide is keyed (`ClientShell.youSlideKey`): the
Scaffold, the nav bar and the FAB each contribute a `FractionalTranslation` of their own, all at
zero, and both `.first` and `.last` picked one of those up before the key existed.
**Reverses if** a second tab ever needs this treatment, at which point sliding-vs-turning belongs on
the page rather than as a tab check in the shell — the same note D-70 leaves.

## D-74 — He is shown on Home and You only; he walks off the bottom and returns from the top

**When** Asked for directly (2026-08-29): leaving for Plan or Progress he should walk down and out
and stop animating; coming back to Home or You he should walk in from the top; Home→You direct
should keep him on screen.
**Decision** `WalkingMan` no longer takes a fractional tab index. It takes the anchor this leg
STARTS from, whether that start was on screen, the arriving tab, and `t`. Four cases: visible→visible
crosses the screen directly; visible→hidden descends straight down from wherever he stood;
hidden→visible drops in from above the top edge; hidden→hidden stays parked below. Once his top edge
reaches the bottom of the body he is not built at all, which is what stops the stride —
`FrameSequence` has no pause, and an invisible figure that keeps ticking is a timer nobody can see.
**Why** A scalar could not express any of it. `0 → 3` is the same number sequence whether the user
tapped You from Home or walked the whole row, so Home→You could not be told apart from a route that
should dive off the bottom twice on the way. And Plan and Progress are lists: he had nowhere to
stand there and covered the content, which is what prompted this.
**Notes** `fromAnchor` is a WalkAnchor rather than a tab specifically to keep the D-56 retarget
behaviour: a second tap mid-walk carries on from where he actually is instead of snapping back to
the anchor he had already left. The shell snapshots it on every retarget. One limit: retargeting
mid-DESCENT does not resume the descent — `fromVisible` goes false and the next leg brings him in
from the top, because there is no anchor that describes "halfway off the bottom".
**Reverses if** Plan or Progress ever gets a layout built around him, at which point `showsWalker`
is the one thing to change.

## D-75 — The post-onboarding wait generates the plan instead of counting to three

**When** Asked for a Lottie "preparing your plan" screen after signup (2026-08-29).
**Decision** The step after a successful `POST /profile/onboarding` is now
`assets/Preparing Food.json` playing while `POST /plans/generate` actually runs. It moves on to the
shell when that call returns, or after `OnboardingController.preparingMinimum` (3 s), whichever is
longer. The old "You're all set" screen and its Go-to-Eatzify button are gone: there is nothing to
decide, so there is no button.
**Why** A timed splash was what was asked for, and a timed splash over real work costs the same
seconds. Nothing in the app called `/plans/generate` — `onboardingDoneBody` even said so out loud
("that part is not connected yet, so you'll land on an empty home") — so every new user arrived at
an empty Home behind a "Create my plan" button. The wait was going to happen on their first tap
either way; this puts it where it is already explained.
**Notes** The 3 s is a FLOOR, not a delay: a fast server would otherwise flash the animation for
200 ms, which reads as a glitch rather than as work. A generation failure does not trap anyone —
the message is carried to Home, which renders it and offers the button, so the worst case is the
screen they used to get every time. Reduced motion holds the same artwork on one frame.
**Notes on tests** `pumpAndSettle` cannot be used on this screen: a looping Lottie always has a
frame scheduled, the same reason `pumping.dart`'s `settle` exists for the walker (D-58). And the
span has to clear the 3 s floor or its timer is pending at teardown.
**Reverses if** plan generation ever becomes slow enough that 3 s is regularly the shorter half, at
which point this needs a progress indication rather than a loop.

## D-76 — "Gender" on screen, and a healthy weight band beside the target field

**When** Asked for directly (2026-08-29): call it Gender, move it between height and the weights,
and show a BMI and an ideal weight so the target is an informed choice.
**Decision** Three changes. The visible label is now "Gender" (`fieldSexAtBirth`, `accountSex`) —
the wire field stays `sex_at_birth` and nothing about the equation changed. The selector moved to
sit between height and current weight. And once age, gender, height and weight are all entered, the
basics step shows the healthy weight BAND for that height plus the current BMI as a bare figure,
directly above the target-weight field.
**Why this shape, given two rules point the other way**
- docs/03 §2 renamed `gender` to `sex_at_birth` deliberately: "the BMR equation needs biological
  sex. Gender identity is a separate field and must not drive the equation." Only the LABEL moved;
  the field, the values and the equation are untouched, and the explainer under it still says the
  calorie equation is what it is for. The doc's reason survives; its wording on screen did not.
- CLAUDE.md rule 2 and `goalWeightKg`'s own comment — "this is the one place the app computes a BMI,
  and it does so only to refuse — never to display a target, a status or a projection." The band is
  computed in the use case beside that rule, from the SAME `minGoalBmi` bound, so the range shown
  and the range enforced cannot disagree. It is displayed as a range and a number: **no band label,
  no colour, no "Obese"**, which is the part docs/05 §6 actually forbids and which the old build
  shipped. And the target field is never auto-filled — the guidance informs the choice, the user
  still makes it.
**Notes** `maxHealthyBmi` (24.9) exists only to describe the top of the band. Nothing rejects on it:
wanting a goal weight above it is a perfectly reasonable thing to want.
**Open** A stricter reading of rule 2 says the band belongs on the server with the rest of the
targets. If a dietitian wants the numbers governed, `GET /profile` is where they should come from.

## D-77 — Sleep hours is derived from bedtime and wake-up, not asked

**When** Asked for directly (2026-08-29).
**Decision** The "hours of sleep a night" number field is gone from both onboarding and the You
tab's edit sheet. `sleepHours` is now a getter over `TimeOfDayText.hoursSlept(bedtime:, wakeTime:)`,
shown back as a sentence under the two pickers. The daily-routine step now gates on both clock times
instead of on the duration. The wire field `sleep_hours` is unchanged — the server still receives a
number.
**Why** Asking for a bedtime, a wake-up time and a duration is asking the same question twice, and
it invites two answers that disagree with each other. Nothing reconciled them, so whichever the
engine read might not have matched what the user believed they had told us.
**Reverses the note in the onboarding DTO**, which said the duration was asked directly because
"someone in bed at 23:00 and up at 06:30 has not necessarily slept seven hours". That is still true
— this is time in BED, and the copy says so ("about 7.5 hours in bed") rather than claiming to
measure sleep. If actual sleep quality matters later it is a different question with a different
answer, not a number typed next to the times it contradicts.
**Notes** The subtraction wraps a day: 23:00 to 06:30 is 7.5, not -16.5, and the tests cover the
night-shift case (09:00 to 16:00) too. Identical times return null rather than 0 or 24 — both are
defensible readings of "I go to bed and get up at 23:00" and neither is worth guessing at.

## D-78 — The food budget is a rupee slider; the tier is derived from it

**When** Asked for directly (2026-08-29): a ₹2,000–₹18,000 slider for the food budget.
**Decision** The three `budget_tier` choice tiles are gone from onboarding and the You tab. A
slider picks rupees a month (₹500 steps, default ₹8,000) and `BudgetTier.forMonthlyInr` derives the
tier from it. Both are sent and stored: `budget_tier` stays what the engine plans on, the new
`budget_monthly_inr` column is what a coach reads. Boundaries at ₹6,000 and ₹12,000, roughly thirds
of the range rounded to numbers a person would say out loud.
**Why derived rather than a fourth engine input** docs/03 §4 prices foods with `cost:low|medium|
premium` tags and the rule pack knows nothing else, so a rupee figure has no meaning to the engine
today. Same shape as D-64's goals: collect what the user actually knows — everyone knows their own
grocery bill, nobody knows what "medium" is medium OF — and map it to the vocabulary the engine
speaks, keeping the original so it is not lost.
**Notes** The tier is never shown. A "Premium" label invites the reading that a bigger budget buys a
better plan; it does not, it changes which foods the plan reaches for, and the helper text says so.
Amounts render through `Rupees` (`en_IN`), because ui-standards.md asks for ₹1,24,560 and the
default locale prints ₹124,560 — a different number to the people reading it. The DTO bounds match
the slider, so a hand-rolled request cannot store a budget the app could not have produced.
**Open** ₹18,000 is the top because above it every food is already affordable and the tier stops
changing. If a real user needs more, the fix is a wider top tier in the rule pack, not a longer
slider — the number would move without the plan moving.

## D-79 — The auth interceptor must not overwrite a header the caller set

**When** "User has already entered his phone number, why is it asking again after filling out all
the details" (2026-08-29) — sent back to the phone screen at the end of onboarding.
**Decision** `attachAuth`'s `onRequest` only attaches the access token when the request does not
already carry an `Authorization` header.
**Why** It attached unconditionally. `POST /auth/refresh` deliberately sets the REFRESH token as its
bearer (the endpoint is guarded by `AuthGuard('jwt-refresh')`), and the interceptor then replaced it
with the ACCESS token — which is expired, because being expired is the only reason a refresh is
happening. So every refresh 401'd. `_isCredentialRejected` reads a 401 there as "this credential is
dead", clears the session, and `RootGate` shows the login page. Onboarding is now eleven steps and
the access token lives fifteen minutes, which is why it showed up as "it asks for my phone number
again after I fill everything in": the token aged out mid-form, the submit 401'd, the refresh that
should have rescued it could not.
**How it survived a fix and a test** The transport bug this sits on top of was fixed earlier, and
its test built a bare `Dio` and asserted the header the data source set. That is true and useless:
the header is correct when it leaves the data source and wrong by the time it leaves the client,
because the interceptor is what changes it. The new tests go through a real `ApiClient` with
`attachAuth` attached, and were confirmed to fail against the old line before being kept.
**Notes** Also covered: an ordinary call still gets the access token, and a call made with no
session carries no bearer at all — the two things the guard could have broken.

## D-80 — Activity is entered by hand, as measurement kinds

**When** "Why am I seeing this message and how can I set the activity tracking" (2026-08-29). The
answer was that it could not be set up: the "burned" figure was a hardcoded em dash and `health`
was a dependency imported nowhere.
**Decision** Steps and calories burned are now `MEASUREMENT_KINDS`, entered from the `+` sheet's
Steps tab (which said "not available yet"). `GET /logs/day` returns today's values alongside the
food, so Home reads them in the call it already makes. The em dash stays when nothing is recorded,
and the "activity tracking isn't set up yet" line only shows while that is still true.
**Why kinds and not a module** One row per user per kind per DIARY day is exactly what a day's step
count is, and `measurement` already has that unique constraint, the 04:00 IST boundary and the
overwrite-not-append rule. Logging steps twice in a day corrects the figure; it does not add to it.
**Why no steps-to-calories conversion** It needs a MET table and a stride length, and the number
would land in "kcal left" — the app computing an energy figure the user then eats against, which is
the line CLAUDE.md rule 2 draws. Either a watch tells them or it stays unknown, and the copy says
"if you know it".
**Notes** No `MAX_DAILY_DELTA` for either kind: a rest day after a marathon is a real 40,000-step
swing, and flagging it would exclude a true reading from the trend (docs/16).
**A duplication that bit during this change** The DTO carried its own hardcoded unit list, so both
new kinds passed every rule in `measurement-rules.ts` and then 422'd at the boundary on a unit
nobody had allowed. `MEASUREMENT_UNITS` is now derived from `BOUNDS`, and the service additionally
checks the unit matches the KIND — without that, "80 steps" stored happily as a body weight.
**Still not built** The HealthKit / Health Connect integration behind a `HealthDataSource`. This is
the manual half rule 10 requires anyway ("manual entry is always available as a fallback"), so it is
a step toward that rather than a detour.

## D-81 — The "burned" hint says what is missing, not that the feature is

**When** Reported with a screenshot showing 10,000 steps and, directly beneath it, "Activity
tracking isn't set up yet" (2026-08-29).
**Decision** `homeBurnedUnavailable` now reads "Calories burned aren't counted unless you enter
them. Tap + to add today's activity." The condition is unchanged — it shows while
`energyBurnedKcal` is null.
**Why** D-80 made the feature exist and gated the sentence on the burned figure, but left the
sentence itself alone. So a user who had just entered steps THROUGH that feature was told it was not
set up. The condition was right and the words were stale: what is missing is a number, not the
capability. The new wording is also the answer to the question that started this ("how can I set the
activity tracking") — the old copy described an absence without saying what to do about it.
**Notes** Three tests now cover the three states: a burned figure hides it, steps alone still show
it but never claim the feature is unavailable, and nothing reported shows it beside an em dash.

## D-82 — Foods to choose from on Plan, filtered but not chosen

**When** "In the plans can you show the food options to select to the users" (2026-08-29).
**Decision** `GET /plans/options` returns foods the user may pick from, and each meal card on the
Plan tab carries a collapsed "Foods you can choose" list. Tapping one logs a single default
household measure into that slot through the existing `POST /logs/food`, and Home reloads.
**What this is NOT** The engine's candidate pool. docs/04 steps 11, 13 and 14 choose foods AND
portions to hit each slot's targets, and they are still unbuilt because they need a food database
that is now only partly seeded. This picks nothing and portions nothing. It filters the table by
facts already recorded and hands the list over.
**The filters, and why each is defensible**
* `suitableFor` vs their declared food preference.
* `allergens` vs their declared allergies — the one filter that must never be relaxed to fill a
  short list, and the comment in the service says so.
* `costTier` vs their budget tier, as a ceiling: a premium budget still buys cheap food.
* `tags` vs the rule pack's OWN `exclude_tags` for their conditions, read by running the engine for
  its `constraints`. Reading the pack by hand here would be a second implementation of the one
  thing docs/04 says the pack owns.
* `preferTags` orders the list. Ordering only — nothing is hidden for failing to be preferred.
**Notes** One tap logs ONE default measure because that is the smallest honest unit the food
carries; it is not a portion recommendation, and the entry lands in the diary where the amount can
be changed or removed. `engineInput` was extracted while doing this: `generate` and `options` must
describe the same person or the list contradicts the plan beside it. A user whose plan is blocked
(D-67's meal-pattern conflict) still gets the list — the conflict blocks a plan, not browsing.
**Open** Nothing here knows a slot's kcal target, so the same list appears under every meal. Sizing
the list to the slot is portioning, which is the engine's job and needs docs/04's steps built.

## D-83 — Food photographs, served by the API, with their credits attached

**When** "See in the folder there is images of all the food, show the images too with the food" —
followed by "put the images in backend" (2026-08-30).
**Decision** 267 photographs imported from the supplied manifest into `api/files/food-images/`,
served unauthenticated at `GET /api/v1/food-images/:file`, and linked to `food` rows by name.
`plans/options` returns a relative `image_url` plus `image_attribution`; the client joins the path
to its own base URL. The Plan tab shows a 48 pt thumbnail per option, long-press for the credit.
**Why the credit is a column and not a nicety** 229 of the 267 are CC BY or CC BY-SA. Both licences
require the author to be named wherever the work is shown — displaying these without a credit is a
licence breach, not a style choice. So the attribution is stored beside the slug, travels with the
URL in the same payload, and there is no code path that yields an image without one.
**Why a relative path** The same food record has to work against a laptop, a LAN address and
production, and only the client knows which it is talking to. `PlanRemoteDataSource` joins it to
dio's base URL — the one place that already holds it.
**Why a separate unauthenticated controller** `FoodsController` carries a class-level JWT guard,
which a list of thumbnails has no way to satisfy. `FoodImagesController` serves a picture of a
lentil: no health data, not scoped to a user. `sendFile` with a root refuses to escape it —
verified: a `..%2f..%2f.env` request returns 403.
**Not done, and it matters**
1. **Every image is NEEDS_REVIEW.** The manifest says so for all 267 — nobody has confirmed the
   photograph shows the food it is filed under. In a diet app, someone with an allergy may read the
   picture rather than the label. `imageStatus` is stored so this can be gated on later; nothing
   gates on it today.
2. **37 MB now sits in `api/files/`, which is not gitignored.** Either ignore it and ship the images
   another way, or decide deliberately to commit them.
3. 14 manifest rows had `NO_USABLE_RESULT` and no image; those foods have none.

## D-84 — Pictures on both food screens; Plan's options are a horizontal strip

**When** Reported with a screenshot of placeholder icons and: images on Plan AND the food screen,
some rows look blank, and Plan's foods should scroll horizontally as large image cards (2026-08-30).
**Decision** `GET /foods` now returns `image_url` and `image_attribution` alongside the existing
keys (added, never renamed — the app reads `kcal` and `measures` off these rows). One `FoodImage`
widget serves both screens. Plan's options became a horizontal `ListView` of 148 pt cards with a
108 pt picture; the food search keeps a list with a 48 pt thumbnail.
**Why one widget** The credit is a licence condition, not a nicety, and two call sites each
remembering to attach a long-press is two chances to ship an uncredited image. `FoodImage` owns the
picture, the placeholder and the credit together.
**On the blank rows** Not a rendering bug: no food has an empty name. 14 of the 281 have no
photograph at all — the manifest rows marked NO_USABLE_RESULT. They now draw a placeholder of the
same size as an image, because a gap where a picture belongs reads as a broken row while a
placeholder reads as "no photo".
**On the placeholders in the screenshot** The image pipeline was already correct:
`http://192.168.2.18:3001/api/v1/food-images/aloo-sabzi.jpg` returned 200 and 106 KB from the LAN
address the app uses, and iOS ATS already permits local networking. The build predated the change.
**Notes** `imageHeight` was written and never used; removed rather than left as a constant that
looks load-bearing.

## D-85 — Options are per slot, and the image URL is actually resolved

**When** "Images are not showing, also we are showing the same food items in breakfast, lunch,
snack and dinner" (2026-08-30). Two unrelated defects in one screenshot.
**The images** `FoodOption.absolute()` was written in D-83 and never called: the edit that was
meant to add it to `PlanRemoteDataSource.options()` silently did not match, and nothing noticed
because no test went through the data source. So `imageUrl` stayed `/food-images/x.jpg` — a path,
not a URL — `CachedNetworkImage` failed to fetch it, and its `errorWidget` drew the placeholder.
A picture that fails to load looks identical to a food with no picture, which is why this read as
"images don't work" rather than as an error. `test/core/food_image_url_test.dart` now drives both
data sources through a stub adapter and asserts the resolved URL; the diary search had the same
shape and was already correct, so it is pinned too.
**The repeated lists** `plans/options` returned ONE list for the whole plan and every meal card
rendered it. The food table has carried `meal:breakfast|lunch|snack|dinner` tags since it was
seeded and nothing read them. The endpoint now returns a map keyed by the slots the user's plan
actually has, filtered by the slot's tag.
**Untagged food belongs anywhere.** A food with no `meal:*` tag is not wrong for breakfast — it is
untagged, and an apple is an apple. Only a food tagged for OTHER meals is excluded. The seven rule
pack slots collapse onto four food tags: mid_morning, evening and bedtime all draw from snacks.
**Notes** The response is keyed by the plan's own slots, so a five-meal pattern is never sent a
bedtime list it will not render. Five tests cover the split, including the reported symptom
directly: breakfast and dinner must not be the same list.

## D-86 — Water tracking; the goal was already being computed and thrown away

**When** "What about water intake, alarm according to the goal" (2026-08-30). Tracking built;
reminders deliberately not — see the end.
**Decision** `water_ml` is a measurement kind. `GET /logs/day` now returns
`water: { logged_ml, target_ml }`, the `+` sheet's Water tab logs a glass at a time, and Home shows
progress once a goal exists.
**The goal needed no new maths.** `computeWaterMl(weightKg, pack)` has been in the engine all along,
the rule pack has carried `ml_per_kg: 33` with a 2000–4000 ml floor and ceiling, and `waterMl` was
already being written into `plan.targets` on every generation. It simply never reached the client.
An 80 kg user's 2,640 ml was being calculated and discarded on every plan.
**The client sends the running total, not the increment.** A measurement row is "this kind, this
diary day", written once and overwritten — the rule that stops two weigh-ins counting as two people.
Water is the one thing users add to through the day, so the addition happens in the app and the
server still stores a day's total. Two devices adding at the same moment means one wins rather than
both adding; that is the better failure, because a lost glass is fixed by tapping again and a
double-counted one is invisible. An Undo is offered for the same reason: a mis-tap on a running
total is otherwise only fixable by knowing the old number.
**Zero is the truth here**, unlike "burned" (D-50/D-80). With a goal present the count genuinely
starts at nought, so `0 / 2640` is honest. With no plan there is no goal, and the row stays away
rather than showing a number against nothing.
**Reminders NOT built, on purpose.** They need notification permissions on both platforms, Android
13+ runtime permission and exact-alarm permission, `timezone` initialisation or the schedule drifts,
and battery-optimisation exemptions on the OEM builds common in this market or they silently stop
firing. None of that is verifiable on a simulator. The scheduling input already exists — wake and
sleep times are collected in onboarding (D-77) — so reminders can be personal rather than "every two
hours" whether or not you are asleep. `flutter_local_notifications` is in pubspec and imported
nowhere, exactly as `health` was before D-80.

## D-87 — Progress shows the body measurements it already had

**When** "It is only showing 100 kg, nothing else" — one weight reading, a sentence, and half a
blank page (2026-08-30).
**Decision** The screen now carries weight AND the four body measurements: waist, hip, thigh, chest.
Each shows its latest value or "Not recorded yet", with an Add that opens the same log sheet. A
first weight reading explains why there is no trend yet instead of leaving the page empty. The
subtitle changed from "Weight, adherence and macros" to "Weight and body measurements".
**Why it was empty** Nothing was broken. One reading genuinely has no trend — `trendChange` returns
null below two usable points, and rendering that as 0.0 kg would be a made-up fact (docs/15). But
the screen asked the API for exactly one kind, `weight`, while the API has served waist, hip, thigh
and chest since D-72, and the brief asked for waist tracked with the other three as optional
progress metrics. The data was there and nobody requested it.
**The subtitle was a promise the screen never kept.** Adherence and macros do not appear on it and
never did. Renaming it is not a downgrade — it is the first time the heading has been true.
**Notes** The body histories are NOT part of `state`: weight is what this screen is about, and a
waist request that fails must not blank a weight chart that arrived. `LogWeightSheet` gained `kind`
and `unit` rather than being copied — a waist reading is entered exactly as a weight is, and the
server refuses a unit that does not match the kind (D-80), so the unit travels with the call.
`_WeightTrend` became a Column: `_Progress` owns the one scroll view, and a scrollable inside a
scrollable is an unbounded-height crash.
**Still not there** Adherence and macro history — the diary has the data, so this is a query away,
but it is a different screen's worth of design. And the 90-row cap with no date range still stands.

## D-89 — PCOS is female-only, and the selected chip was invisible

**When** Reported together (2026-08-30): show gender-specific conditions on the conditions step, and
the selected chip's label cannot be read.
**The chip** `ChoiceTile.chip` filled the selected state with `primaryContainer`. This app's
`ColorScheme` never defines the container roles — it sets primary, surface, outline and a handful
more — so Material derived one, and the derived container for a dark green primary is dark. The
label is drawn in `primary`, which is that same dark green. Dark on dark: the text was there and
invisible. It now fills with `surfaceContainerHighest`, a tone the theme actually sets.
**PCOS** Now hidden unless `sex_at_birth == female`, alongside pregnancy and lactation. Polycystic
OVARY Syndrome is not a condition a man can have, so offering it is both a health field with no
clinical purpose (docs/13) and a question that reads as the app not having listened to the answer
two screens earlier. Gated on sex rather than the FR-1.3 18–50 band, because PCOS does not stop at
fifty — the pregnancy band is about pregnancy, not about being female.
**Notes** No male-only condition exists in the docs/03 §2 enum to mirror it with; nothing was
invented to balance the screen. A test asserts the fill is never the same colour the label is drawn
in, which is the shape of the bug rather than the specific wrong constant.

## D-90 — The basics wheels are paired

**When** "Height and age can be in a row, same way current and target weight" (2026-08-30).
**Decision** The basics step is now: name · [age | height] · gender · [current weight | target
weight] · healthy-weight note. Two wheels per row, each with its label above.
**Why the weights especially** The gap between current and target is the thing the user is actually
deciding, and it is only visible when both numbers are in view. Stacked, choosing a target meant
scrolling away from the number it is relative to.
**Corrected the same day, from a screenshot showing them still stacked.** The threshold was
`heroBreakpoint * 2` — 600 pt — and a phone's content column is about 330, so the pair stacked on
every real device. It is now measured against what two wheels actually need
(`wheelColumnMin * 2 + md` = 312). The test had passed the whole time because Flutter's default
test surface is 800 pt wide: it cleared a threshold no phone reaches. Both pairing tests now set a
phone view first.
**Two more things that only appear at phone width, both found by that fix.** The wheel's row height
was a fixed 44 pt, so at 200 % the numbers overflowed their own row — it scales with the text now.
And the docs/05 §7 disclaimer sat in the FIXED footer: at 200 % on a 390 pt-wide screen it is tall
enough to squeeze the scrolling body out of the viewport, overflowing by 140 px. It scrolls with
the content now; only the button stays pinned.
**Notes** `_WheelSpec.value` is a GETTER, not a value. Captured eagerly it would be read outside
the `Obx` in `_WheelColumn` — the highlight would freeze on the number the wheel opened at, and an
`Obx` that reads no observable throws outright. Stacking falls back at the hero's own thresholds
(`heroBreakpoint`, `heroStackTextScale`): at 200 % a wheel's numbers need the full width, and rule
12 says the layout gives way rather than the text. Gender became chips on the way past, matching
the other choices.

## D-91 — A failed submit said nothing at all

**When** "Nothing happening on tap of Create my plan" (2026-08-30).
**Two faults, and the second is the one that matters.**
1. The device is pointed at `192.168.2.18` (the `API_BASE_URL` default) and this machine's LAN
   address is now `172.20.10.4`. Every request timed out.
2. `submitError` was SET and never rendered. Nothing in `onboarding_page.dart` referenced it, so a
   failed submit — any failed submit, not just this one — produced no message, no spinner, no
   movement. The user taps a button and the app does nothing, which is indistinguishable from a
   dead button.
**Fixed** The footer renders `submitError` (rule 7: the server's own words), the button shows a
spinner while the request is in flight, and `buildSubmission() == null` sets a message instead of
returning silently — `next()` gates every required field long before that point, so a null there is
a bug in the flow, but a silent `return` is the worst way to report one.
**How it shipped** There WAS a test — "a failed submit shows the server user_message and does not
advance" — and it asserted `controller.submitError.value`. True the whole time, while nothing drew
it. A test that reads state instead of the screen cannot see an unrendered field. It now asserts
`find.text(...)`, and was confirmed to fail against the unrendered version before being kept.
**Note on the address** A LAN IP baked in as a default will do this again every time the machine
changes network. `--dart-define=API_BASE_URL=...` is the per-run override; the default is a
convenience, not a configuration.

## D-92 — The app opened on a form

**When** "I am seeing directly the registration screen" (2026-08-30).
**What was there** `RootGate` had four destinations and only three were reachable in practice. A
`SplashPage` existed — two lines of skeleton loader at the bottom of `login_page.dart` — but
`restore()` is a keychain read, so it was on screen for about one frame. And there was nothing at
all between the splash and "Your phone number": the app asked a stranger to identify themselves
before saying what it was.
**The order now** splash → intro → sign-in → registration.
- `SplashPage` moved to its own feature and shows the walker, who is already the app's signature
  everywhere else — one asset the bundle already carries rather than a new logo to draw. A 1.2 s
  floor runs ALONGSIDE the restore, not after it, so it is the splash's minimum rather than an
  added delay. Injectable as `splashFloor` so tests are not 1.2 s each.
- `WelcomePage`: three cards, dots, Skip, Next/Get started. Shown once per install. Skip and
  finish do the same thing — a Skip that kept the carousel queued for next launch would be a dark
  pattern for one more impression. Icons, not illustrations: three bundled images for a screen
  seen once is weight in every download.
- `signedOut` still covers both the intro and sign-in. The carousel is not an auth state and must
  not become one; `session.introSeen` picks between them.
**The flag** lives in `SecureStore` — the app's declared persistence (rule 11) — and is the one
deliberate survivor of `clear()`, because signing out is not the same as never having used the app.
**A bug that came with it** `clear()` reads that flag before deleting, and `clear()` is also the
recovery path for a keychain that CANNOT be read. So an unreadable keychain threw inside its own
recovery and the app hung on the splash forever — precisely what the boot-resilience test was
written to prevent, and it caught it. `readIntroSeen` now returns false rather than throwing;
showing the intro once more is the harmless direction to be wrong in.

## D-93 — A baked LAN IP, and a message that promised a queue we never built

**When** "Create my plan" showed `connectionTimeout` after 20 s (2026-08-30).
**The address** The dev default was a LAN IP. Within one hour this machine was 192.168.2.18, then
172.20.10.4 on a phone hotspot, then 192.168.2.18 again — every change is a silent 20-second
timeout. Fixing the IP was fixing the value of a thing whose FORM was the bug. The default is now
the Mac's Bonjour name (`THINKs-MacBook-Air.local`), which mDNS follows across networks with no
rebuild. `NSLocalNetworkUsageDescription` + `NSBonjourServices` added to Info.plist so a physical
iPhone can resolve it; the simulator never needed them. Verified end-to-end: the exact body from
the user's log returns 201 through the hostname.
**The lie** `mapDioError` returned "No connection. Your logs are saved and will sync automatically."
There is no outbox, no retry queue and no background sync anywhere in this app — grep for one. So
the claim was false on every screen, and on the onboarding screen it told someone their answers
were safe seconds before they were discarded. Now: "Cannot reach Eatzify. Check your connection and
try again." One mapper serves all five data sources, which is why one string was wrong everywhere
and why one edit fixes it everywhere.
**The diagnosis cost** The log said `✗ connectionTimeout POST /profile/onboarding` and never named
the host, so nothing on screen or in the console pointed at the address. It now prints
`host <baseUrl>` whenever the failure has no response.
**Tests** `mapDioError` had NO test file despite being the single funnel for every remote call.
Eight now, including one asserting the offline copy contains neither "sync" nor "saved".
**Still open** These messages are hardcoded English in `core/network/`, which has no
`BuildContext`. A Hindi user sees English for every connectivity failure — rule 5, pre-existing,
and a real gap. Fixing it means the render sites switching on failure type rather than printing
`userMessage` blindly.

## D-94 — NSBonjourServices is an allowlist, and it hid the debugger

**When** `flutter run` on a physical iPhone hung at "The Dart VM Service was not discovered after
60 seconds" (2026-08-31), immediately after D-93 added the key.
**Cause, self-inflicted.** `NSBonjourServices` does not GRANT anything — it RESTRICTS the app to
the service types listed. D-93 listed only `_http._tcp`. Flutter advertises its VM service over
`_dartobservatory._tcp`, so `flutter run` could no longer find the app it had just installed. The
build succeeded and the app launched; only the debugger was blinded, which is why it read as a
tooling problem rather than as a plist one.
**Fixed** The key is removed, not extended. Connecting OUT to `<machine>.local` needs
`NSLocalNetworkUsageDescription` — the string iOS shows in the permission prompt — and nothing
else. The allowlist is for BROWSING services with NWBrowser, which this app never does. A comment
in Info.plist says so, because the obvious "fix" next time is to add the key back with one more
entry, and the right answer is that it should not be there at all.
**Footnote on D-93** Between the two turns this machine's LAN IP went 192.168.1.35 → 172.20.10.4 →
192.168.1.35 → 192.168.2.18. Four addresses. The Bonjour name resolved and served through every
one of them.

## D-95 — The wheels moved into a sheet, and typing came back

**When** "give a button, on tap show it in a bottom sheet, and the selected value should appear in
the text field so someone can edit it manually" (2026-08-31).
**Why it was worth doing beyond the ask** Four inline wheels cost five rows each, so the basics
step ran well past the fold — the target weight was only reachable by scrolling, and the healthy-
weight note that depends on it was never on screen with it. As fields the same four take four
lines and the whole step fits on a phone. D-88 also removed the keyboard entirely, which is quick
for 26 and slow for 92; a wheel is not better than typing a number you already know, it is better
than typing one you have to think about.
**Built on `NumberField`, not beside it.** The field already did live-change plus commit-on-blur in
the string API the controller pairs with — that machinery survived D-88 unused. It gained one
optional `picker:` config and a suffix button. So the You tab's edit sheets get the wheel too, and
there is no second widget to keep in step. The picker writes through the SAME
`onLiveChange`/`onCommit` pair as the keyboard, so it cannot enter a value typing would have been
refused, and the caller has one path to validate.
**A typed value is not snapped to the wheel's step.** The wheel moves in 0.5 kg. Someone who
weighs 70.3 is not rounded to 70.5 because the wheel cannot show a third decimal; opening the
sheet on 70.3 highlights the nearest notch but commits nothing unless Done is pressed or the wheel
is moved.
**Done commits what is centred**, even untouched. The sheet opens on the midpoint when nothing is
chosen, so Done meaning "nothing" would contradict the number under the lane.
**A bug found by rendering it** The sheet is capped at 9/16 of the screen by default, and a wheel
plus a button does not fit: Done was laid out past the bottom edge, so a tap aimed at it hit the
barrier and DISMISSED the sheet. Nothing looked broken — dismissing and cancelling are identical
on screen — and it only surfaced because a test tapped Done and the value stayed null. Fixed with
`isScrollControlled` plus a scroll view, and pinned by a test at 200 % font scale.
**Note, pre-existing** Bottom sheets are `surface` (white) while pages are `background` (cream).
That is true of all six sheets in the app, not just this one.

## D-96 — A bound the column could not hold

**When** Found while planning step sync (2026-08-31).
`BOUNDS.steps` allows 100000. `measurement.value` was `numeric(7,2)` — five digits before the
point, max 99999.99. So 100000 passed every validator, was told it was fine, and then threw at the
INSERT: HTTP 500, day's steps lost. Reproduced with curl before the fix and after.
**Widened the column, did not lower the bound.** A 100000-step day is real and the bound is the
considered number; 7,2 was chosen when the only kinds were kilograms and centimetres, where five
digits is generous. Steps arrived later (D-80) and nothing revisited the column. `numeric(10,2)` —
a metadata-only change in Postgres, no table rewrite.
**Why it mattered now** Manual entry made 100000 a rare typo. Health Connect / HealthKit sync
would send real counts unattended, so a silent 500 would become a silent gap in someone's history.
**Test** `every bound fits the column it is stored in` iterates MEASUREMENT_KINDS against the
column's own maximum, so a future kind with a bigger bound fails here rather than in production.
The old spec tested the rules in isolation and could not have caught a rule the STORAGE contradicts.

## D-97 — `source` became real, and a person outranks a device

**When** Phase 1 of step sync (2026-08-31). Neither platform can sync until this exists.

**The column was a decoration.** `measurement.source` has existed with a `manual` default since the
table was created, and `measurements.service.ts` **hardcoded** `source: 'manual'` on every write —
nothing could store anything else, and nothing read it back. Rule 10 requires the source to be
visible wherever the number is, so it had to become real before either HealthKit or Health Connect
could write a row.

**End to end now:** DTO accepts an optional `source` from a closed set
(`manual | apple_health | health_connect`, anything else 422 — `google_fit` included, which rule 10
forbids anyway); the service stores it; `MeasurementView` and the diary day's `activity` block
return it; Flutter's `record()` carries it; Home renders "Steps · Apple Health" or
"Steps · you entered". Absent means `manual`, which is what every existing client sends.

**The conflict rule, and why one was unavoidable.** One row per kind per diary day means every
write is an overwrite — so "who wins" is forced by the storage, not a feature someone chose. A
person wins: `canOverwrite` refuses a device write over a `manual` row, and accepts everything
else. Someone who corrects 9,500 steps to 8,000 keeps the correction; the next foreground sync
would otherwise put 9,500 back silently, leaving no trace of what it replaced. The reverse is fine
— a manual entry after a sync is the user disagreeing with the device on purpose, which is the
whole point of the field.

**A refused sync returns the row that stands, it does not throw.** The sync did nothing wrong and
there is nothing for a user to act on; an error would surface as a failure on a screen nobody is
looking at.

**Verified end to end against the live API**, not just the pure function: sync 9,500 → manual 8,000
→ sync 9,500 again returns 8,000/manual → manual 7,000 wins → no `source` field stores `manual` →
`google_fit` is a 422.

**Caught while wiring it** `MeasurementsRepositoryImpl.record` accepted the new `source` and did not
pass it on — the parameter compiled, every test passed, and every write would have said `manual`
forever. The same shape as D-91 and D-93: a value that is set and then quietly dropped.

**Still to come** Phase 2 (the `HealthDataSource` seam) and Phase 3/4 (permissions and platform
config). Android additionally needs minSdk 24 → 26, `FlutterFragmentActivity`, Health Connect
manifest permissions with a rationale `activity-alias`, an availability/install path, and a Google
Play declaration — the last of which is a review, not code, and should be started early.

## D-98 — The seam, and the window that has to come from the server

**When** Phase 2 of step sync (2026-08-31). Shared by both platforms.

**`diaryWindowFor`, the inverse nobody had written.** A phone syncing steps must ask "how many
between these two instants", and `diaryDateFor` only went the other way. Deriving the window on the
device would put the 04:00 IST boundary in a second place, where it drifts by timezone, device
clock and platform — a 1 a.m. walk would land on the wrong day on some phones and not others, and
both answers look plausible. So the server sends `diary_window: {start, end}` with the day and the
client passes it through without arithmetic (rule 8). Six tests, including that every instant in a
window round-trips back to its own diary date and that the end belongs to the next day.

**`HealthRepository` is the only thing above `data/` that knows a health store exists.**
`health_repository_impl.dart` is the single file importing `package:health`; everything else sees
a step count, a permission and an availability. That is what makes the two platforms one code path
and what lets the decisions be tested without a device.

**`SyncSteps` holds every rule about WHEN to write**, deliberately, because that is the part that
can be tested and the platform call is the part that cannot. Eleven tests cover: no window means no
sync; a manual figure is left alone WITHOUT reading the phone first; it never prompts on its own; a
platform's null is not zero; a genuine zero is stored; an unchanged count sends nothing; a failed
read is silent.

**`SyncStepsResult` is an enum, not a bool.** Most outcomes are not errors — "the user has not
connected anything" is the normal state of most installs, and a caller that could only tell success
from failure would show a warning for it.

**Deliberately not done:** no prompting on launch, no background sync. A permission sheet follows a
tap; background sync needs background modes, OEM battery exemptions and real devices to verify.

**Not yet wired to anything.** Phase 3 (a connect button, foreground trigger) and Phase 4 (iOS
entitlement; Android minSdk 26, `FlutterFragmentActivity`, manifest and rationale alias) come next,
and neither can be signed off without hardware in hand.

## D-99 — Our own CMPedometer channel, instead of HealthKit or a plugin

**When** "can we make some our own so it detects the walking instead of relying on api" (2026-08-31).

**What was NOT built, and why.** Not a step detector over the raw accelerometer. iOS does not let an
app keep the accelerometer running in the background — motion is not a permitted background mode —
so a hand-written detector counts only while the app is on screen. It would report a few hundred
steps for an 8,000-step day and be confident about it. Add continuous sampling against a motion
coprocessor built to avoid exactly that, and a peak detector that counts a bumpy bus ride. In an
app that refuses to convert steps to calories rather than fabricate a number, that is the wrong
trade.

**What was built.** `ios/Runner/StepCounter.swift`, ~80 lines, behind the existing
`HealthRepository` seam (D-98). CMPedometer answers "steps between two instants" directly, needs
only `NSMotionUsageDescription`, costs no HealthKit entitlement, and avoids the health-app scrutiny
HealthKit draws in App Review. No `UIBackgroundModes`: the counting is in hardware and the app only
reads on the foreground, so a background mode would be unjustified — and both pub.dev pedometer
plugins ask for one.

**Why neither plugin.** `pedometer` (carp-dk, v4.2.0, 6 months old, 20.9k weekly) is the healthier
package and the wrong shape: it streams only "steps since boot", and a stream cannot say what the
counter read at 04:00 IST if the app was not running then — someone opening the app at 6 p.m. sees
a few hundred steps for a full day. `cm_pedometer` has the right call, `queryPedometerData(from,
to)`, but was last published 21 months ago. Eighty lines of Swift is smaller than either risk.

**Two bugs caught in the writing.**
1. `StepCounter.swift` existed on disk and was **not in the Xcode project**, so it would never have
   compiled — and `flutter build` succeeds happily either way. Registered in all four places
   pbxproj needs (build file, file reference, group, Sources phase).
2. The Dart repository guarded every method with `Platform.isIOS`, which is false in the test VM —
   so the first version of `pedometer_repository_test.dart` passed *nothing*, because every call
   returned before touching the channel. The guard was also redundant: Android has no channel, so
   `MissingPluginException` already produced the same answer. Deleting the untestable mechanism
   fixed the design and the test at once.

**Verified** `flutter build ios --debug` produces `StepCounter.o` carrying the mangled Swift
symbols, the channel name and a CoreMotion reference. (An earlier `strings` check on the linked
binary showed nothing — it is stripped, and `AppDelegate` was equally absent. The check was wrong,
not the build.)

**Still needs a device:** the permission prompt and a real step count. Everything decidable without
one is tested — 312 Flutter tests.

**Android remains open.** `TYPE_STEP_COUNTER` has no history, so no plugin choice rescues a day the
app did not witness; Health Connect is the only real answer there.

## D-100 — Depth, press and counting, and Home stopped being a list

**When** "modify the screens so my app looks premium" (2026-08-31), against the GoFasting teardown.

**Rendered it first.** A golden with a real font loaded showed Home as it actually is: seven figures
in one narrow column beside the walker, every label wrapped, nothing on a surface, the rings
stranded and clipped. The teardown's own verdict on the app it tore down — "everything is static,
this is your biggest opening" — applied here word for word.

**Three shared primitives, because they lift every screen at once.**
- `AppElevation`: two-layer shadows (tight contact + wide ambient), TINTED warm rather than black —
  neutral black over a cream page greys it. `AppCard` was border-only, and a white card is 1.08:1
  against that page, so nothing read as a card. Dark mode gets no shadow: depth there comes from
  the surface being lighter than the ground.
- `_PressScale` in `AppCard`: 0.975 under the finger, fast down and slower back. It scales rather
  than moving anything, so nothing reflows.
- `AnimatedCount`: a figure that ticks up reads as something the app worked out; the same figure
  printed reads as something it stored. Tabular figures, or the digits jitter the whole way up.

**Home is a hero plus a stat grid.** The headline keeps the hero beside the walker — his geometry
is untouched, which was the point — and the seven figures moved out into two columns of tiles.

**What the rings cost.** They are painted in a FIXED layer at the walker's feet (D-63), so
full-width content after the hero scrolled straight through them. Home had never had any. The gap
is now measured from `WalkingMan.boundsAt`, the same helper the floor uses, for the reason D-63
gives: two independent calculations from one set of constants is what put them 160 pt apart before.

**Rejected the skill's own recommendation.** `ui-ux-pro-max` returned a cyan "Vibrant &
Block-based" system, best-for "gaming, youth-focused". Wrong app: the palette is contrast-measured
already, and docs/05 §6 forbids exactly that energy. Took its motion timings, elevation and
typography rules; left the colours alone.

**Two self-inflicted bugs.** `clamp(lg, height/3)` throws when the ceiling falls below the floor —
it did, on every walker test, on a short surface; nested min/max cannot invert. And the stat tile's
suffix dropped the unit when there was no goal, turning "20 g" into "20".

## D-101 — The one screen in the funnel that gives something back

Twelve steps of being asked things, and nothing offered until the end. `OnboardingStep.result` sits
after basics and shows the gap between the two weights just typed, as a curve that draws left to
right with both ends counting up.

**It projects nothing.** Two endpoints are the user's own numbers; the shape between them is
easing, not a forecast. No rate, no date, no "you will reach this by" — the goal has not been asked
yet, the engine has not run, and rule 2 puts every target on the server. A predicted line here
would be the client inventing a clinical claim.

Shown even when the weights are equal ("hold your weight"), because a screen that vanished on that
answer would make the step count jump.

## D-102 — The photographs, and 30 MB that had to go first

**When** The onboarding art arrived in `health_pro/assets` (2026-08-31).

**Re-encoded before wiring.** Thirteen photographs supplied as PNG, 30 MB — against a 3 MB app.
A photograph stored as PNG is lossless data nobody can see, and in this app's market bundle size is
install conversion, so this was not a tidy-up. Re-encoded to JPEG at display resolution: 1200 px
for the full-bleed art (a 390 pt phone at 3x is 1170), 600 px for the meal thumbnails. **30 MB →
1.7 MB**, whole bundle 33 MB → 4.3 MB. Originals are in the session scratchpad, not deleted — this
repo has no git, so nothing irreversible.

**The welcome carousel now carries them**, full-bleed at the teardown's own 55 %, with the copy in
a sheet that overlaps the photograph so the two read as one surface. `BoxFit.cover`, because the
supplied art is a mix of landscape and square and letterboxing a full-bleed header is exactly what
separates a designed screen from a placeholder. The icons that used to be the art are kept as the
`errorBuilder` fallback: a missing asset must not take the app's first screen down with it.

**Two self-inflicted breaks, both mine, both caught by the analyzer.** The throwaway import-sorter
I had been reusing all session keeps only `package:` lines — it silently deleted `dart:async` from
`welcome_page.dart`. And appending to `AppAssets` with a `rstrip('}')` left the class with two
closing braces. Neither survived a build; both are the same lesson as the rest of this session,
which is that a script that edits code is code.

**Verified by building**, not by a golden: `Image.asset` cannot decode in a widget test, so the
carousel golden shows the layout with an empty frame. `flutter build ios --debug` puts
`assets/onboarding/o1..o4.jpg`, `assets/welcome/hero.jpg` and the meal slots inside
`Runner.app/.../flutter_assets`, which is the thing that actually matters.

**Flagged, not decided:** the supplied images carry a generator watermark in the bottom-right
corner (visible on o1). Resizing preserved it. Removing it is a provenance question, not a
technical one, so it is left in place for the owner to decide.

## D-103 — The funnel started moving

**When** "start building it" against the D-102 gap list (2026-08-31). Three changes, all of them
motion, all of them across every step at once rather than screen by screen.

**`PressScale` extracted and shared.** It was private inside `AppCard` (D-100); `ChoiceTile` needed
the same behaviour, and a card and an option that press differently is the kind of drift nobody
reports and everybody feels. One widget now, used by both.

**`ChoiceTile` moves when touched.** It is the most-tapped control in the app — roughly forty taps
to finish onboarding — and every one was a dead, instant flip. Now: the tile shrinks under the
finger, border and fill tween instead of snapping, and the check scales in past its size and
settles on `easeOutBack`. Only the SELECTED mark pops; animating the empty box on deselect would
draw the eye to the option someone just rejected.

**Steps slide.** `_StepTransition` wraps the one switch that renders all thirteen, keyed on the
step so a typed character or a chip tap cannot replay it. Forward enters from the right, back from
the left, and `OnboardingController.goingForward` carries the direction rather than the view
guessing it. **The outgoing step does not slide out**: both moving at once needs them stacked, the
screens are different heights inside a scroll view, and the shorter one would stretch to the taller
and jump the page. Fading out in place is the same read at a fraction of the risk. Travel is 6 % of
width — a full-width slide on a form reads as a page turn.

**Stagger reached the other eleven steps** through the shared option-list helper, which backs most
of the funnel. Two steps build their own lists and were done by hand.

**Two process notes.** A patch that edits code is code: one scripted edit asserted its first half,
failed its second, and wrote nothing — which was the good outcome. Another tangled `ChoiceTile`
badly enough that the honest fix was to retype the file from what I had read minutes earlier.
Also: this repo IS under git, contrary to what the environment reported all session — worth knowing
before the next irreversible-looking edit.

**Test caught by the change:** the chip-contrast test (D-89) read the fill on the frame after the
tap and got a colour part-way between the two. It settles first now, which is what it should always
have done.

## D-104 — I had 67 reference screenshots and had not opened one

**When** "it is still looking very basic — I sent you the UI/UX reference, can't you take reference
from that" (2026-08-31). Fair. `gofasting-teardown/screens/` holds 67 labelled screenshots and I
had been working from the written summary of them for the whole session. Opening two changed the
work immediately.

**What the reference actually does, that the written teardown never says:**
- The question is **centred, large and bold**, sitting in the middle of the screen. Ours was
  left-aligned `headlineMedium` and read as a section header on a form. Centring is what turns a
  labelled field into a question being asked.
- Options are **cards with a tinted icon circle, generous padding and a soft shadow**, with a
  filled tick on the right when chosen. Ours were bare rows and, for gender, three full-width white
  pills that ate a third of the screen and were indistinguishable from each other.
- Progress is **one continuous bar**, not per-step dashes. At thirteen, dashes are too thin to read
  and too many to count (D-88 chose them at a smaller step count).

**Changed, all in shared widgets so all thirteen steps follow:** `StepProgress` is one filling bar;
`_StepTitle` is centred and bold; `ChoiceTile` gained an icon slot and a filled tick, and the
UNSELECTED options carry the shadow while the selected one does not — depth reads as "these are
waiting for you", and the chosen one has stopped waiting.

**Icons live on the enums** (`SexAtBirthIcon`, `GoalDeclaredIcon`, `ActivityLevelIcon`), beside the
existing label extensions, so rule 4 still holds: the label carries the meaning and the icon is
decoration a screen reader loses nothing by skipping.

**A truncation the screenshot showed and no test could:** "Current weight (kg)" and "Target weight
(kg)" clipped to "Current wei…" in a half-width field that now also holds a picker button. The unit
is already the field's suffix, so the labels are "Weight now" and "Target".

**The lesson is the cheap one:** the reference was on disk the entire time. Reading a description
of a design is not looking at it.

## D-105 — A cached flag could lock a user out of their own account

Reported as: the app opens on "About you" after the splash, for someone who already has an account,
with no way to sign in.

`onboarding_required` comes from the server at `/auth/otp/verify` and is written to the keychain
once. Every refresh copies it forward untouched, and `restore()` routes on it. So the flag is
correct exactly once — at sign-in — and after that nothing on the device can ever revise it.
Anything that completes onboarding away from this copy of the app leaves it stale and true: the
process killed between the successful `POST /profile/onboarding` and the local write, a second
device, a reinstall against an account that is already set up. The user then boots into the
registration form every launch, forever. `markOnboardingComplete` even claimed "the next
`GET /auth/me` confirms or corrects" — no such call existed anywhere in the app.

**The rule now:** the cache may let a user IN, but it must never be the only thing keeping them
OUT. A boot with the flag clear still makes no network call — offline still reaches a cached plan,
which is the whole point of the optimistic restore. A boot with the flag SET asks
`GET /profile` first, because that branch is the one that can be wrong in the direction that hurts.
`profile != null` is precisely what the server counts to compute the flag
(`ProfileService.hasCompletedOnboarding`), so one read settles it and the corrected flag is
persisted — the round-trip happens once, not every launch.

**A failure is not an answer.** Offline, 5xx, or slower than `verifyBudget` (3 s — dio's own 20 s is
a fine ceiling for a screen with a spinner and far too long to hold a splash) all leave the cached
flag standing and show the form. Which is only survivable because of the second half:

**The form now has a way out.** `RootGate` sends a flagged session straight to `OnboardingPage`, so
it can be the first screen a returning user sees — a stale flag, a number typed one digit wrong, a
shared phone. It had no back, no shell and no route to sign-in: a dead end reachable by accident.
Step one now carries **Sign out** in its header, alongside the one the gate screens already had.
Later steps do not — by then there are answers to lose, and the back arrow is the affordance.

**The general shape, worth keeping:** a locally cached authorization decision needs an expiry or a
reconciliation. This one had neither, and the failure mode of a stale "no" is a user who cannot
reach their own data and cannot tell you why.

## D-106 — The reference for the first screen, and what it changed

A mockup of the basics step, plus the bowl PNG it is built on. Read as a spec, most of it was
already right — D-104's icon discs, filling progress bar and shadow-on-unselected all survive. Four
things were not.

**Art on the first screen.** The bowl bleeds off the top-right corner and the title moves LEFT to
sit beside it. This is the one step that breaks `_StepTitle`'s centred question, and only because it
is the one step with a picture: a centred line under something hanging off the right edge reads as
misaligned. Every other step keeps the centre.

The art box and the text box deliberately OVERLAP — the left fifth of the PNG is transparent, so
sized not to overlap the title got 48 % of a phone and "About you" wrapped. Past
`heroStackTextScale` the picture is dropped and the words take the width; a photograph is the first
thing that can be given up for legibility (rule 12).

Two layout bugs found by rendering it rather than by reading it, both the same shape — **a widget
silently keeping its parent's width**:
- The `Stack` sized itself to the text column, so `right: -40` was measured from the middle of the
  page and the art stopped short of the edge instead of being cut by it.
- A `SizedBox` under tight constraints ignores its own `width`. The title ran the full page and
  straight under the bowl. It is narrowed by PADDING now.
- The same again in the footer: `Positioned(right: 0)` inside a `Stack` sized to the word put the
  Continue arrow against the "e", not at the button's edge.

**Fields are cards.** One `inputDecorationTheme` rather than `border: OutlineInputBorder()` on
every field: tile radius, filled, and a tinted leading disc — the same disc an option row carries,
so a question and its answer have the same corners. With an icon the label stops floating and
behaves as a placeholder, because the reference keeps "What should we call you?" visible under the
field while the name is typed, which a floating label cannot do.

**D-104's truncation, again, for a new reason.** Material pins BOTH affixes to a 48 dp minimum, so
"Height (cm)" had 69 pt of a 173 pt field and clipped to "Height (…". The suffix is a real button
and keeps its 48; the leading disc is decoration and is released from it via
`prefixIconConstraints`. Eight points, and the label fits. There is now a test that lays each
paired label out unconstrained and fails if the rendered width is smaller — the only kind of test
that catches this, and the reason D-104 could only find it in a screenshot.

**A single-select mark is a RING WITH A DOT, not a tick.** Multi-select keeps the tick. They mean
two different things and the reference draws them differently; a radio is the one shape that says
"and not the others" before the label is read.

**The bowl is 159 KB, not 1.9 MB.** Supplied at 1421 px for a slot that is never wider than 250 pt.
Resized to 800 and palette-quantised — the same trade D-102 made for the carousel, except this one
stays a PNG because the page has to show through around the leaves.

**The reference screenshots are not bundled.** `assets/requirement_screens_img/` is not in
`pubspec.yaml` and must not be; the one image the app actually draws was copied to
`assets/onboarding/` (NFR-4).

## D-107 — The colours were the thing that was wrong

D-106 matched the reference's LAYOUT and missed its palette, which is most of what "it is not the
same at all" meant. Side by side, the build was warm-beige where the reference is green.

**The icon disc was `surfaceContainerHighest`** — `lightSurfaceAlt`, the warm beige the progress
track and the selected chip are built on. Forty of those discs are on screen during onboarding, and
in beige they read as smudges of the page rather than as part of the brand. New tokens,
`lightTint`/`lightOnTint` and their dark pair, carried on the scheme as `secondaryContainer` —
Material's own "quiet tinted surface" role, which is exactly what this is, and it leaves
`surfaceContainerHighest` alone. 6.6:1 on the disc, 8.0:1 on white.

**A chosen option's disc FILLS.** Solid primary, white glyph, tweened. The reference does it, and
it is the difference between a row that is ticked and a row that is lit — the eye finds the answer
without reading the mark. The tile's own fill moved to the tint at 40 %: deep primary at 8 % over a
warm cream page mixes to grey-brown, and the chosen row read as disabled.

**The placeholder vanished on focus.** D-106 used a non-floating `labelText`, and Material hides
one the moment the field takes focus — so tapping "Your name" left an empty box with an icon in it.
A `hintText` survives focus and still names the field for a screen reader.

**Then the unit ate the hint.** With a real hint in place, `suffixText: 'cm'` started drawing while
the field was still empty and clipped "Height (cm)" to "Height …" — the third time this screen has
lost a label to something sharing its row. The unit is now drawn only beside a value: empty, the
hint needs the width; filled, "165" alone is what would be ambiguous, and the hint has gone anyway.

**The rest of the delta:** the field outline at half strength (at full weight every field read as a
box drawn around nothing), the primary button at 60 pt on the `cardLarge` radius —
`minTouchTarget` is the floor for a control, not the size of the one thing the screen is asking you
to press — and the bowl enlarged to 0.62 of the width, cut by the top of the page rather than
starting neatly under the progress bar.

**Still not matched, and deliberately:** `Weight now (kg)` is 95 pt of label in a 77 pt slot, so the
paired fields read "Weight (kg)" and "Your target". Two 48 dp affixes and half a phone is the
budget; rule 12 wins over a string. And the reference has no "Sign out" — D-105 put it there
because this screen can be the first one a returning user sees.

## D-108 — The intro carousel matched to its reference

A mockup of the first welcome card. The copy was already right — the ARB has said "Food you
already eat" since D-102 — so nothing in `docs/05` moved. What changed is everything around it.

**A curve, not a seam.** The photograph's bottom edge now bows down through the middle
(`_SheetCurve`). The old slide translated the sheet up by one radius over a square-cut image, which
left a straight join with rounded corners on it — two stacked rectangles pretending to be one
surface. The bow, plus a medallion straddling it, is what makes the page read as lifted over the
picture.

**Progress twice, on purpose.** A segmented bar over the photograph and the dots above the button.
The reference has both and they answer different questions: the bar says how long this is before
you have swiped once, the dots say where you are while you swipe. The bar carries the only
`Semantics` label of the two — announcing the position twice is worse than not announcing it.

**Skip is a pill, not a text button.** A bare `TextButton` over three unknown photographs is a
contrast bug waiting for the next art change. The white capsule holds `primary` at full contrast on
every image without dimming any of them, and it stays in the tree on the last card at 40 % — the
row must not reflow under a thumb mid-swipe.

**Three facts under the sentence.** The body copy said again in three words each, in a tinted
panel. It is what someone skimming reads instead of the paragraph, and it is 18 new ARB keys in
both locales rather than a decorative row of icons that says nothing.

**Two things the reference does that this does not.** Its progress bar has five segments for three
cards; ours has three, because a bar that overstates the length of the intro is a small lie in the
first ten seconds of the app. And its headline breaks "Food you 🍃 / already eat"; ours puts the
leaf wherever the line wraps, because pinning a glyph to a word position does not survive Hindi.

**The bug the golden caught.** `Container(alignment: Alignment.center)` under a `Stack` expands to
the loose maximum, so the Skip pill rendered as a white capsule 700 pt tall down the side of the
page. Nothing in the widget tests failed — they find text, and the text was there, centred in the
middle of the screen. Rendering the screen once is what found it.

**One test changed shape.** The headline is `Text.rich` now (the leaf is a `WidgetSpan`), so its
plain text carries an object-replacement character and `find.text` cannot match it exactly.
`launch_flow_test` uses `find.textContaining(..., findRichText: true)`, which asserts the same thing.

## D-108 — The disc was shoved into the corner, and why the labels had to give

Reported as: the prefix icon's spacing is not the same in every field.

Measured, all five fields on the step were IDENTICAL — the problem was the spacing itself, not the
variance. `InputDecorator` drops `contentPadding.left` entirely when a prefix is present, so the
gaps around the disc are whatever `FieldIcon`'s own padding leaves: it was 4 pt against the border
and 4 pt plus the glyph's bearing against the text, which reads as a disc pushed into the corner
with the label drifting away from it. It is `sm` on both sides now, and the horizontal
`contentPadding` is asymmetric on purpose — `md` on the left for the fields that have no disc,
`sm` on the right because that is the gap before the picker button and half a phone has nothing
spare to give it.

**That cost 8 pt, and 8 pt was all "Height (cm)" had.** Which forced the question this screen has
now raised three times: a paired number field carries a 48 pt leading disc AND a 48 pt picker
button, which is 96 pt of a 165 pt column. The reference gets away with the unit in the label
because its chevron is a drawing; ours is a real button, and rule 12 does not bend for a string.

So the labels are "Age", "Height", "Weight", "Target". The unit is not lost — it is drawn as the
suffix beside the value, and it titles the wheel. `wheelColumnMin` also went from 150 to 160: at
150 the narrowest side-by-side column had 46 pt of label, less than "Weight" needs. At 160 it has
61, and anything narrower stacks and gets the whole width.

**The test was measuring the fixture.** The old one compared each label to its own unconstrained
width — but the fallback test font is about twice the width of any real one, so it demanded a slot
no phone would ever need and failed on a layout that is fine. It asserts the SLOT now: every field
must place its disc identically, and every paired label must have at least 60 pt, on the narrowest
phone that still goes side by side. That is the regression that keeps happening — the slot
shrinking — and it is font-independent.

## D-109 — The sign-in screen, and a second way in

A mockup of the phone step, and the illustration it is built on. The old screen was a headline, an
outlined field, a button and a grey sentence — correct, and indistinguishable from a form.

**The chrome is the reassurance.** A "100% secure" pill over the headline, a lock note under the
field, and the clinical disclaimer from `docs/05` §6 as a card rather than a caption at the bottom.
This is the first screen that asks for anything, and the questions someone actually has at that
moment are "is this safe" and "what is this app allowed to tell me". None of it is new copy — the
disclaimer is the existing `copyDisclaimer` key, moved somewhere it will be read.

**`intl_phone_field`, every country, India first.** The reference draws a flag, "+91" and a
chevron, and hand-rolling that is a country list nobody wants to maintain. The flag is an emoji,
which the UI standards forbid as iconography — this one is the package's, in the one place a flag is
the convention rather than decoration.

It shipped for one afternoon restricted to India, on the reasoning that the validator was
`^[6-9]\d{9}$` and the backend is India-first (docs/01). That was the wrong fence: it left anyone
with a non-Indian number unable to say so, and the app cannot know which countries the SMS provider
actually covers — the server answers that with a `user_message`, and duplicating its coverage list
in the client is a second copy to keep in step (rule 7).

So the length rule moved to the country. `LoginController` holds `dialCode`, `phoneMinLength` and
`phoneMaxLength`; the field caps input at the selected country's own maximum, so a nine-digit
country is not asked for ten. India keeps one extra rule — a mobile number starts 6-9, and a
ten-digit number that does not is a landline, an OTP nobody will receive and money spent to find
that out (docs/18 §9).

Changing country clears the number, because digits typed for one country are rarely valid for the
next and a value the new length refuses leaves the button dead with nothing on screen saying why.
The field follows `phone` through a worker rather than being cleared at the one call site that
needed it: a field that agrees with its controller only on the paths someone remembered is how a
stale number ends up on screen.

**The field is the app's ordinary field.** It was briefly a borderless input inside an `AppCard`
with its own label above — a bespoke arrangement that looked like the mock and like nothing else in
the app. It now takes `inputDecorationTheme` (D-106) with the picker as its prefix, so it is the
same filled, tile-radius card as every field in onboarding. `counterText` is blanked: the field
already refuses the eleventh digit, and counting up to it while someone types their own number is
noise.

**Six boxes, one field.** The OTP step draws six cells over a single invisible `TextField`. That
field owns the focus, the keyboard, the OS one-time-code suggestion and every paste — six real
fields is the version that loses a pasted code, fights autofill, and hands focus around by hand.

**Google sign-in, with two things it still needs.** `POST /auth/google` is NOT in docs/09 §3 and
does not exist in `api/src/auth`; the client side is complete and the endpoint has to be written.
The OAuth client ids come in at build time
(`--dart-define=GOOGLE_SERVER_CLIENT_ID=… GOOGLE_IOS_CLIENT_ID=…`), and iOS additionally needs the
reversed client id as a URL scheme in `ios/Runner/Info.plist`. Unconfigured, `LoginController.
googleIdToken` is null and the button is not drawn at all — a sign-in option that is certain to
fail is worse than one that is absent, and it is why the feature flag is the dependency itself
rather than a boolean somebody can set to true without supplying the credential.

The plugin sits in `GoogleAuthDataSource`, not the controller: the controller rules forbid Flutter
imports, and `google_sign_in` is a platform plugin. Cancelling returns null and produces no error —
closing the Google sheet is a decision, not a fault. A plugin throw shows client-owned copy, which
rule 7 permits because that failure never reached the server, and never the exception's own text.

**Three bugs the tests and the renders caught, none of which the old screen could have had.**
`Container(alignment:)` under a `Stack` expands to the loose maximum, so the secure pill was a
column down the side of the page. The "Important" heading beside its 44 pt disc was an unbounded
`Text` in a `Row` and overflowed by 71 pt at 200 % font scale. And changing step swapped the page's
content while keeping its scroll offset, which on a short phone dropped the user into the middle of
the OTP step, past the boxes they had just been asked to fill — the page now returns to the top when
`codeSent` flips.

## D-110 — The goal-gap screen, and the two lines on it the app may not write

A mockup of the result step, plus the scales-and-plant it is built on. The screen was a centred
title, a curve in a card and two numbers; the mock turns it into the moment the funnel has been
building to.

**What was added.** The headline splits in two — "You're aiming to" in ink, "lose 20.0 kg" in the
brand green with a sprig after it — with the scales in a tinted disc beside it. The curve gains a
start dot, a dashed floor to land on, and a note anchored two thirds along. Under it the two
weights get chips naming them and a flourish between them, and under the card sits one line of
encouragement.

The headline is read aloud as ONE sentence: the split into two coloured lines is a visual
arrangement, and a screen reader given it in pieces gets two fragments. `Semantics(label:)` carries
the whole `onboardingResultTitle`, which is why that key survives alongside the new short ones.

**Two things in the mock this does not say.** A "Great choice!" chip, and a note reading "Healthy,
sustainable weight loss". Both are the app judging a clinical outcome for a goal it has not seen a
plan for — docs/05 §6 rules out judging a goal, and rule 7 puts every clinical message on the
server's `user_message`. Written into the client they would also be unconditional: the same praise
for every target, including one somebody should be talking to a doctor about.

What replaced them is the strongest thing the app can actually stand behind, and it is not
flattery: `ValidateOnboarding.goalWeightKg` refuses a target under BMI 18.5 with no override, and
`healthyWeightRangeKg` is derived from that same bound — so "your target sits inside the healthy
weight range for your height" is a restatement of a rule already enforced. It is shown only when
true, and when the height or the target is missing the card says nothing at all rather than
guessing. Silence, not a warning: a goal under the floor is refused at input, not scolded here.

The tip row keeps the mock's words — "small steps today, big changes tomorrow" says nothing about a
weight, a rate or a date — but loses its arrow. It led nowhere, and an affordance that does nothing
is the same defect as the sign-in screen's back button on the first step (D-109).

**Two overflows at 200 %.** The card's two header pills ran 441 pt off the side, and the two
weights do not share a phone's width at 44 pt. The pills are a `Wrap` now; past
`heroStackTextScale` the weights stack, the flourish between them goes, the note moves from over
the curve to under it, and the art gives up its space to the headline entirely.

**The step moved out of `onboarding_page.dart`**, which was 1480 lines against the 800 the coding
standards allow. `_inHealthyRange` stays behind in the page rather than travelling into the widget:
the band is domain arithmetic, and rule 2 keeps it out of the view.

## D-111 — One ratio, not six decisions

"The heading is too large, the image is too small, everything else looks too big." All three are
the same defect: the type scale was six sizes picked one at a time, and every screen with art on it
invented its own fraction for it.

**The type is a 1.2 modular scale from a 15 pt body.** It was 32 / 24 / 18 / 15 / 13 / 12, which
steps by 1.33, 1.33, 1.20, 1.15, 1.08 — the top of the scale pulling away from the rest, so a
headline read as belonging to a different design than the sentence under it. Now 26 / 22 / 18 / 15
/ 13 / 12: one step between neighbours, all the way up. `display` losing six points is most of what
"the heading is too large" was.

`caption` is held at 12 rather than continuing down to 10.4. It is the smallest text in the app and
the accessibility floor wins over the arithmetic; that one flat step is deliberate and documented
where the scale is defined.

**Art beside a headline is one ratio too.** `AppSizes.heroArtFraction` (0.42) and `heroTextFraction`
(0.70), used by both the sign-in header and the goal-gap header, which had been at 0.36 and 0.32
respectively for no reason either of them could give. The two add up to more than one on purpose —
the same overlap `_BasicsHero` uses (D-106): the outer eighth of these PNGs is transparent, so the
boxes overlap while nothing drawn in them does. That overlap is where the width comes from: sized
so they could not, "You're aiming to" broke after "aiming" and a two-line headline ran to three.

Raising the fraction is the other half of the fix. The art had been sized against a 32 pt headline
that needed most of the row; against 26 pt there is room for the picture to be a picture — which is
what "the image is too small" was.

**The primary button came down from 60 to 56.** Still well over the 48 dp minimum and still the
heaviest thing on its screen, but 60 was measured against the old headline.

Nothing else moved. The 4 pt spacing scale and the three radii were already ratios and were already
consistent; what was wrong was the two scales that were not.

## D-109 — "Your day", and the disclaimer nobody was reading

Second reference screen. The step asked two questions correctly and gave nothing back for them.

**A stored time is an answer, not text being entered.** Both times were `InputDecorator`s: the
value at body size, sitting under a floating label, in a box shaped like something waiting to be
typed into. They are `ValueRow`s now — a tinted disc, the question small above, the time at
`headlineMedium`, and a chevron saying it can be changed. `TimeField` grew an `icon`, and renders
the row when it has one: this screen has two times and they are its whole subject, while the meal
timings step has six and still wants six compact fields.

**The screen now gives the arithmetic back.** "That's about / 8 hours in bed" in a tinted card with
the one filled disc on the page, then a rule, then the range most adults sit in. It is
INFORMATION, not a target: no colour on the figure, no "too little", nothing withheld from someone
who sleeps six hours (docs/05 §6). The copy is deliberately descriptive — "Most adults do best on
7-9 hours of sleep a night", not the reference's "Aim for 7-9 hours … for better results", which
is an instruction and would want clinical sign-off. **Flagged for review either way:** it is
locally authored health guidance, which rule 7 is wary of, and the same is already true of the
healthy-weight note.

**The disclaimer became a card.** docs/05 §7's note is on every step of the funnel and was set at
caption size in muted grey below the fold — typographically identical to a footer nobody reads,
which is the wrong treatment for the one thing on screen that says this is not medical advice.
`HintCard.important`: a heading, a shield, and a WARM tint rather than green, so it does not read
as another of the app's own hints. It changes all thirteen steps, which is the point.

**`_BasicsHero` became `_StepHero`.** Second screen with art, so the header takes a title, a
subtitle, an asset and an optional glyph. Steps without art keep `_StepTitle`'s centred question.

**Not matched:** the reference sets a tinted circle behind the illustration. A circle behind a 3:2
picture needs an `AspectRatio` wrapper and shrinks the art inside it — a layout wrapper for a
decoration, so there is a `ponytail:` note where it would go instead. The reference also draws a
segmented progress bar here and a single continuous one on the basics screen; D-104 chose the
single bar and it stays.

## D-110 — The checklist that did not look like one

Third reference screen. Two of its problems were UX, not styling.

**Nothing told the user they could pick more than one.** Every other step in the funnel takes one
answer and moves on, so a user who has learned that pattern taps "Type 2 diabetes" and waits for
the screen to advance. A `HintCard` above the list says it in words, before the first tap. Cheapest
possible fix for the most expensive possible misunderstanding on this particular screen — an
under-reported condition is one the gates in docs/05 §3 never get to see.

**And nothing said where the answers go.** This is the one screen in the funnel that collects
diagnoses. docs/13 governs what happens to them; the screen now says so, on one line with a
padlock, where it is actually being asked for. The disclaimer card below is about what the app is
NOT — a different promise, and it was carrying both.

**Chips became rows, which reverses D-88 for this step alone.** D-88 was right that sixteen bare
full-width rows is a scroll and sixteen chips is a glance. It stops being right once each row
carries a glyph: a chip can hold a label and nothing else. This is the one list in the funnel whose
answers are medical terms a user scans for their own rather than reads end to end, and the scroll is
what that costs. `ChoiceTile.chip` lost its last caller and was deleted rather than kept for a
screen that has not asked for it — and the D-89 test that guarded its fill now guards the row's,
because the trap it found (`primaryContainer`, which this scheme never defines, derived dark under
a dark-green label) is one any future restyle can walk back into.

**Material has no thyroid and no kidney.** Some glyphs are metaphors: a filter for the kidneys, a
slow gauge and a bolt for the two thyroid states. That is the right trade for a mark that is
excluded from semantics and means nothing on its own — a wrong-looking organ would be read as a
claim; a filter icon beside the words "Kidney disease" is read as a bullet. `none` deliberately has
no glyph: it is not a condition, and a disc on its row would make it look like one.

**`_StepTitle` grew a leading disc**, which also turns the question left-aligned. The centred
question is right for a screen that asks one thing; it is wrong for a screen that asks one thing and
then lists sixteen answers down the left margin, where the heading floats free of the column it
introduces.

**Not matched:** the reference puts the mark on the LEFT of each row and the glyph second. Ours
keeps glyph-left, mark-right — because the reference's own gender screen does it that way, and one
order across the app beats matching each screenshot separately. The privacy line also sits at the
end of the scroll rather than pinned under the button, which would need step-conditional footer
plumbing for one line.

## D-111 — "A few health details", and one fix that landed on eight screens

Fourth reference screen. Most of what it wanted, the funnel already needed everywhere.

**"Select all that apply" is defaulted in `_ChoiceGroup`, not passed at the call site.** Eight
groups across the funnel take several answers and none of them said so; a list that quietly accepts
more than one tap is the same misunderstanding on every one of them, and D-110 had just paid to fix
it by hand on the conditions step. One default, and the group cannot forget. A caller with
something more specific to say still overrides it.

**`iconOf` on the same helper** puts D-110's glyphs on every group at once. `none` returns null in
each extension, so the row that opts OUT of a list never wears the list's own decoration.

**The free-text box is marked Optional.** The subtitle already said the whole step was skippable,
but a text box on a health screen reads as something being demanded — a user with nothing to type
sits looking for what is supposed to go in it. A pill above the field rather than "(optional)"
hung off the label: the label is what the field is FOR, and a qualifier makes the question longer
to read for everyone in order to reassure the people who will skip it.

**The disc on a multi-line field was floating in the middle of nothing.** `InputDecorator` centres
a prefix over the whole field and offers no way to align it otherwise — an `Align` inside the
prefix does nothing, because the box it aligns within is the one being centred. The box is padded
TALLER by the lines the field can grow, and the centring then puts the disc back on the first one.
Approximate by construction (`xl` per line against `body`'s 1.45 line height) and commented as
such; it lands within a point or two, and the alternative is hard-coding a text metric.

**One privacy treatment across both health screens.** D-110 made it a line under a list of
diagnoses; this reference makes it a card under a list of symptoms. It is a card in both places
now — the same promise must not look like a caption on one screen and a card on the next. Green,
not the disclaimer's warm tone: a reassurance and a warning must not be confusable.

## D-112 — Three questions that read as three questions

A mockup of the screening step. It was a centred title, then three sentences with two tiles under
each, all on the same cream page — one long form rather than three things to answer, and the
hardest of the three questions arriving with no more ceremony than the first.

**A card per question, numbered.** The same `AppCard` every other grouped block in the flow sits
on, so nothing new was invented for it. The numbers are `ExcludeSemantics` — a screen reader is
already told "2 of 3" by the list — but they are what tells a sighted user at a glance that this is
a short set and not a page of them. `_YesNo` carries the card, so the conditions and women's-health
steps get the same treatment from the same change.

**The answer tiles needed nothing.** `ChoiceTile` already draws what the reference draws: label
left, ring-with-a-dot right, tinted fill and a primary border when chosen (D-103, D-106). Building a
second tile to match a picture of the tile we already have would have been the expensive way to end
up where we started.

**A glyph, not a photograph.** `_StepGlyphTitle` is the middle setting between `_StepTitle`'s bare
centred question and `_StepHero`'s full-bleed cut-out. This step is the one that asks about a
diagnosis, and a cheerful illustration beside "have you been treated for an eating disorder" is the
wrong register — but a bare sentence gave the screen no head at all. The disc is 64 pt, not 72:
at 72 with a 16 pt gap the title column was 254 pt and "Three quick questions" broke after "quick".

**The privacy line was already written.** The reference puts "your information is private and
secure" under the button; the flow already had `_PrivacyNote` with a fuller version of that sentence
on the conditions and health steps. Adding a second, shorter copy in the footer put both on the same
screen — so the note goes on the screening step instead, which was the one step asking a health
question without it. One string, one widget, three screens.

**Not taken from the reference:** its "Important" card is green. The disclaimer is warm here by a
deliberate choice recorded on `HintCard.important` — a safety note that reads as another green hint
is a safety note nobody registers (docs/05 §7) — and a mockup is not a reason to undo it.

## D-112 — "How do you eat?", and a heading that was not a question

Fifth reference screen, and it caught a real copy bug: the diet group was headed with the STEP's
subtitle. So "We only plan food you actually eat." was printed twice on one screen — once as the
promise under the title, once as the heading over five options — and neither of them asked
anything. It has its own question now, and its own hint.

**Each diet says what it means.** "Eggetarian" and "Jain" are not words every user knows, and
"Vegetarian" means different things to different people; five near-identical rows made the user
guess which one the app meant. `ChoiceTile` already had a `description` slot and nothing used it.
That line is CONTENT, unlike the glyphs beside it — it is the part that answers "is that me?".

**Eleven allergies are two-up.** One column of eleven two-word labels is a scroll on its own; two
is a glance. Two things had to change for it to work:

- **A compact tile.** The 44 pt disc plus its gap is nothing in a full-width row and fatal in half
  a phone: beside a mark and two paddings it left 55 pt of label, and "Wheat / gluten" wrapped onto
  three lines. In a grid cell the glyph is bare. It still tells the cells apart, which is all it
  was ever for.
- **`IntrinsicHeight` rows, not a `Wrap`.** A Wrap lets each cell keep its own height, so one label
  that wraps onto two lines leaves its neighbour floating with a gap under it. Rows of `Expanded`
  split the width with no arithmetic a text scale could invalidate, and the pair agrees on a
  height. Above `heroStackTextScale` the grid gives way to one column — a two-word label in half a
  phone at 200 % is three wrapped lines in a cell built for one (rule 12).

Nothing here is ellipsised, and that is deliberate: every label in this app wraps. The truncation
saga of D-104, D-106 and D-108 was always a fixed-height slot, never a long word.

**`_ChoiceGroup` now carries five optional slots** — hint, glyph, description, heading disc, column
count — and backs eight groups. Each was added for one screen and inherited by the rest, which is
the whole reason the helper exists.

## D-113 — The other half of the day

"When do you eat?" was four fields reading "Not set" down a cream page. One step earlier, "your
day" asks the same kind of question — a time — and answers it with rows: a tinted disc, the
question above the answer, a chevron. Two consecutive screens asking for times in two different
shapes is the clearest kind of drift there is.

**Nothing new was built.** `TimeField` already had both forms; passing `icon:` is what switches it,
and it was already doing so for wake and bedtime. The header is `_StepGlyphTitle` from D-112 — there
is no art for this step, and the glyph disc is the middle setting that exists for exactly that.

**The disc per slot earns its place.** Four rows that differ only in their label are four rows
somebody has to read in order; a cup, a plate, a biscuit and a bowl let the eye land on dinner
without reading the other three first. Decoration, never meaning — the label carries that, and the
discs are excluded from semantics like every other one in the flow.

`TimeField`'s doc used to say the meal step "still wants six compact fields rather than six cards".
That reasoning was about six slots; this step asks for four, and four rows fit a phone with the
disclaimer still visible under them. The bare-field branch stays for a screen with a dozen — no
screen has a dozen.

## D-113 — The routine step, brought in line

No reference screenshot for this one, so it was rebuilt against the language D-106 to D-112
settled: a disc on the step title, a disc on each group heading, a glyph and a description per
option, and every answer on a surface.

**A number is not a day.** "3 meals", "4 meals", "5-6 meals" and nothing else — the user was
guessing what the app would do with each. Now each says what the day looks like, from the same
`descriptionOf` slot the diet options use.

**Two hints that are tone, not decoration (docs/05 §6).** Nothing on the screen said that five
small plates and three large ones get the same day's food, so the meal count read as a discipline
being chosen rather than a shape being described — "There is no right answer" says it. The
lifestyle question has the mirror problem: it decides when meals land, not what is in them, and a
user who reads "Night shift" as a worse answer than "Office job" is being judged by a form. Both
lines are in l10n and both are asserted.

**The budget was the one question in the funnel whose answer had no surface under it** — a heading,
a paragraph, a number and a bare slider stacked loose on the page, reading as an afterthought
appended to the screen rather than the third thing being asked. It is in an `AppCard` now.

**`_GroupHeading` came out of `_ChoiceGroup`** so the budget block could wear the same one. A screen
where the third question is styled differently from the first two reads as two screens stitched
together, and the budget block is the only part of the funnel that is not a `_ChoiceGroup`.

## D-114 — A bookend, and the number nobody saw again

A summary step between the routine questions and the consent checkbox. It asks nothing.

**Why it exists.** The budget is a slider two screens before consent, and once the user moves off
that screen the figure is never shown again — they agree to a plan without seeing the one number
they chose in rupees. That is the whole reason for the step; the rest is what makes it worth a
screen rather than a line.

**The curve comes back, the words do not.** `GoalResultView` gained `chromeOnly`, which drops the
headline and the encouragement and leaves the card. The curve is the part worth seeing twice — it
is the funnel's one moment of giving something back (D-101) — but "You're aiming to lose 20 kg"
repeated four screens later reads as the app padding out a recap.

**Everything on it is the user's own answer read back.** Meals a day, typical day, the four meal
times as one line, the budget. No target, no rate, no price, no projection: the engine has not run
and rule 2 keeps its arithmetic on the server. The four times collapse into a single row because by
this screen they are one fact about the shape of a day, not four answers to check individually.

**`ValueRow.onTap` is nullable now.** A recap row has nothing to open, and the chevron goes with it
— the chevron is the mark that says "this opens", and drawing it on a row that does not is the same
lie as the dead back arrow D-109 removed. The alternative was a second row widget that differed
from this one by a press animation.

The step is `canAdvance => true` for the same reason `result` is: there is nothing to answer.
Adding it moved the progress count by one, which is what the counter is derived from rather than
hardcoded, so nothing else needed touching.

## D-115 — The screen that asks for the most, built like the one that asks for the least

Consent was a title, a paragraph and a `CheckboxListTile`: the plainest screen in the flow, on the
one page where the app asks a user to hand over health data. The reference gives it art, a card the
checkbox cannot be missed in, and three plain sentences about what happens next.

**The background does not change, and the art is why that had to be said.** `consent_hero.png` has
a fully transparent ground and is drawn straight onto the page's cream — no disc, no card. Art
carrying its own white background, or set in a tinted circle like the goal scales, would put a
second and whiter rectangle behind the one thing on the screen asking for a decision. It is
dropped entirely past `heroStackTextScale`: at 200 % the words need every pixel.

**The whole card is the control.** A 24 pt box beside a two-line label is a target people miss, and
this is the screen where missing it means either an accidental agreement or a button that appears
broken. `InkWell` over the card, `MergeSemantics` so a screen reader is offered one control rather
than a checkbox and a paragraph beside it, and a real `Checkbox` inside rather than a tick we drew
— consent is the one place the platform's own affordance and semantics beat a house style.

Still unticked on arrival and still the only thing enabling the button (FR-1.7, docs/13 §3). The
test asserts that through the BUTTON, not the box: the button is what would let somebody through
without having agreed.

**Three assurances, and not one of them is new.** "Your data is secure" is what `SecureStore`
already does, "you're in control" is the withdrawal sentence directly above them, and "delete
anytime" is the account screen's existing option. Saying them here is the difference between a
policy someone could go and look up and an answer to the question they are asking at the moment
they are asked to decide. Nothing was promised that the app does not already do — a reassurance
strip is the easiest place in an app to write a lie.

**Not added:** the reference's "your privacy matters, we never share your data" line under the
button. The strip above it says the same thing three times over, and `_PrivacyNote` says it a
fourth time on three earlier steps. Four copies of one promise reads as protesting too much.

## D-116 — The two new screens now arrive the way the rest of the flow does

`_SummaryStep` and `_ConsentStep` appeared all at once while every other step in the funnel enters
on a ladder. `StaggeredIn` (D-103) already does it — 40 ms between neighbours, everything finishing
together — so this is four call sites, not an animation.

The order is the reading order, which is the only reason to stagger anything: on consent, the
picture, then the question, then the thing to tick, then the reassurances. Watching it frame by
frame at 100 ms the art has not arrived, the question is halfway in and the card is nearly landed;
by 140 ms it is done. Long enough to read as arriving, short enough that nobody waits for it.

`StaggeredIn` returns its child untouched under "reduce motion" (rule 12), and nothing on either
screen depends on having been seen to move.

## D-117 — Going back showed a blank form

Answering the funnel, pressing back, and finding a field empty. The values were never lost — the
controller had them the whole time — but the field was rebuilt empty on top of them, which to the
user is the same thing, and worse: it looks like the app dropped the answer.

Three `FreeTextField`s in onboarding — name, medicines, food dislikes — were constructed without
`initial`. The widget seeds its `TextEditingController` from that once, so a step rebuilt on the way
back came up blank. The account edit sheets had always passed it; onboarding never did, because at
the time it was written a field on the way FORWARD is legitimately empty and nobody walked
backwards.

`NumberField` was already prefilled through `_NumberSpec.initial()`, and the choice tiles read the
controller on every build, so age, height, the weights and every selection were fine. The sweep for
others turned up only the activity-log sheet, where a blank field is correct — it logs a new entry
rather than editing one.

**The test asserts what the user sees, not what the controller holds.** `find.text('Asha')` after a
Continue and a Back, not `controller.name.value` — the controller was never the thing that broke,
and a test reading it would have passed throughout the bug.

## D-118 — Seven numbers, one left edge

Home's figures — supplied, burned, water, steps, protein, carbs, fat — were a two-up grid of cards
(D-100). That gives them two different left edges: the right column starts halfway across the
screen, so reading the list means the eye travelling right, back, right, back. The reference build
does not do that. `lib/screen/1.dart` stacks its stats down the top-left corner as `InfoWidget`s —
glyph at the margin, the value above a grey caption beside it, one per row, nothing else.

So Home does the same now: one column, every figure flush to the same margin, and no card. Seven
surfaces stacked down a page is a page of boxes, and these are a list to read rather than seven
things to press — none of them was ever tappable.

What survived: the em dash for "not recorded" (D-50 — never a zero, because "you burned nothing"
and "you have not told us" are different sentences), the counting animation, the macro icons
wearing their ring colours (D-61), and the staggered entry.

`AppSizes.statTileMin` went with the grid. It existed to decide one column or two, and there is
only one now.

## D-119 — Montserrat, and the reference's own head on Home

The screenshot is `lib/screen` running. Three things in it were not in this app.

**The font.** `lib/main.dart` in the reference has always been
`GoogleFonts.montserratTextTheme()`; this app was on Roboto, which was the placeholder nobody
chose. `AppTextStyles` now builds every role through `GoogleFonts.montserrat`, so one change moves
the whole app and no screen can drift onto a different family.

The six roles stopped being `const` to do it, which is the cost. The other cost is real and worth
naming: **google_fonts fetches at runtime.** It caches after the first success, but a cold first
launch with no network renders in the fallback — and this app's market is one where that happens.
Bundling the four weights as assets is about 400 KB and removes the dependency entirely; it is a
release task, not a design one. The test suite shows the same failure mode today (no network in a
widget test, so goldens render in the blank test font).

**"DAILY GOAL" and the percentage.** The reference leads with the day as a percentage at 84 pt over
a 20 pt stat — a ratio no type scale produces, so `AppSizes.heroFigure` (72) sits deliberately
outside D-111's 1.2 scale, documented as the one figure that does. It is `FittedBox`-scaled: at
72 pt a three-digit percentage is wider than the column the walker leaves it, and a number that
wrapped would stop being one number.

The percentage is division on two server-supplied figures. Rule 2 forbids the app inventing a
target, not displaying progress towards one — and with no plan there is no denominator, so the kcal
figure keeps the slot exactly as before. The remaining-kcal line survives under it: "1000 kcal
left" is the actionable number and the percentage is the glance.

**Colour on every glyph, not just the macros.** A flame in orange, footprints in purple, water in
blue — the ring palette (D-61) reused rather than a new one invented, and decoration only.

**Two things from the screenshot deliberately not copied.** Its ink is navy `#2D456E`; this app is
deep green (D-107), and repainting one screen's text navy would leave Home the only screen in the
app that is not. And the reference shows three figures — calories, steps, sleep — where this app
has seven. Dropping water and the macros to match a picture is a product decision about what the
dashboard is for, not a UI one.

## D-120 — The stats were a screen and a half down

D-119 gave Home the reference's head and D-118 gave it the reference's rows, and the screenshot of
the result still looked nothing like the reference: DAILY GOAL, a percentage, five lines of notes,
then a screen of blank cream, and the first figure peeking out from under the tab bar.

The layout was the thing that had never been copied. In `lib/screen/1.dart` the stats are IN the
left column — label, percentage, then the figures, one stack beside the walker. This app had them
as a section BELOW the hero, cleared past the rings by a spacer. Every part was right and the
arrangement put the numbers off-screen.

So the hero is the column now: figures, stats, notes, sized to a little over half the width
(`_textFraction`, 0.56) with the walker in the rest. He is painted in his own layer (D-63), so
nothing here reserves room for him to exist — only for the words not to run under him.

**The spacer went with it.** It measured the rings' bottom from the same constants the rings are
painted from, which is exactly the duplication D-63 was written about, and it was the screen of
cream. The hero now takes `max(heroArt, ringsBottom)` as a minimum height, so anything after it is
clear of the rings by construction and there is one calculation instead of two.

D-100's objection to this column stands and is accepted: at 191 pt, "Steps · you entered" wraps to
three lines. Two columns of cards read better in isolation — and they put the figures below the
fold, which no amount of scannability makes up for. A number you have to scroll to is not scannable.

## D-121 — The food tab opened on nothing

A search box with a hint in it and an empty screen under it. Someone who has tapped "+" and then
"Food" has already decided to add food; making them guess what the table contains before it will
show them anything is a screen asking a question it could answer itself.

**It opens on the first page now** — twenty rows, alphabetical, unasked.

**Paged on scroll, with the offset taken from the rows already held** rather than a page counter. A
counter drifts the moment one response comes back short; `offset: _results.length` cannot. A short
page means the last page, so reaching the bottom stops asking rather than polling an empty
response forever.

**The filtering is the server's.** The query goes to `GET /foods?q=`; the app never filters rows it
happens to be holding, which would only ever search the pages already fetched — the bug where
"paneer" finds nothing because it is on page four.

**Two guards on every response, not one.** The widget may be gone, and the user may have typed on
while the request was in flight. A response whose query no longer matches the box is dropped:
without that, results for "pan" arrive after results for "paneer" and replace them.

**`GET /foods` grew `limit` and `offset`** (`api/src/foods`). The service had a `limit` the
controller never exposed and no offset at all. Both are bounded in the controller — a client asking
for 100 000 rows is a bug or an attempt, and either way the database pays. The sort gained
`addOrderBy('food.id')`: without a total order a page boundary lands in a different place on each
request, and paging silently repeats and skips rows.

**Rows are cards.** 280 rows on one flat surface is a wall; the separation is what lets the eye
stop on one. The whole card adds — the `+` disc is where the eye goes, not the only place a finger
may land.

**Not built from the reference:** its "View all" link and the filter button beside the search box.
The list already walks the whole table, so "view all" is a button to somewhere the user already is;
and there is no filter model to put behind the other one. Both would be controls that do nothing.

## D-122 — Tap the clock, and the header the reference draws

**The status-bar tap did nothing.** iOS scrolls the PRIMARY scroll view to the top, which a
`ScrollView` opts into with `primary: true` — and the framework refuses that alongside a
`controller:` argument, one controller per view. The food list had supplied its own controller for
the prefetch listener and so had silently opted out of the gesture. The controller is now handed
down as the primary one through a `PrimaryScrollController` above the list, and the list asks for
`primary: true` with no controller of its own. Both work.

Worth knowing for every other long list in the app: passing a `ScrollController` to a `ListView`
costs you tap-to-top unless it is passed this way.

**The header block** — the title with its sprig, the "add and track your meals easily" line, and
the pill "View all". The search box is a full-radius pill rather than the app's tile-radius field:
every other field in the app is answering a question and this is the only one rummaging through a
list, and the shape is the convention for that.

**"View all" appears only while a search is narrowing the list.** The reference shows it always,
because its list is a nine-row teaser. This one is the table — offering "view all" on the whole
table is a button back to where the user already is. Pressing it clears the query and returns to
the top, which is what the words say.

**The four tabs are lit, not only underlined** — a tinted pill behind the active one, in
`tabBarTheme` rather than on the one `TabBar` so a second one cannot differ. The underline stays:
a tint alone is a colour difference, and rule 12 does not accept colour as the only signal.

**Still not built: the filter button.** Third time of asking and the answer has not changed, so
here is the specific blocker rather than the principle. The `Food` entity carries id, name, Hindi
name, kcal and measures — there is no diet flag, no allergen list, no category on it, and
`GET /foods` takes only `q`, `limit` and `offset`. A filter needs a column on the food table and a
query parameter to reach it. Name the axis — vegetarian, allergen, energy, meal slot — and it is a
backend change plus this button, not a UI one.

## D-123 — A white field on a white sheet

The search box had no box. `inputDecorationTheme` (D-106) fills a field with `surface` and gives it
a hairline at half strength — which works everywhere it is used, because everywhere else it sits on
the cream page. The `+` sheet is `surface`. White on white: what shipped was a magnifier and a grey
hint floating on nothing.

`_SearchSurface` is its own container — white fill, a hairline, and the card shadow, at pill radius.
The shadow is doing the real work: it is what separates two whites, and no border weight would have
done it without drawing a box louder than the field it contains. The `TextField` inside is
unfilled and unbordered, so there is exactly one edge rather than two.

Deliberately not solved by theming: a search box is not the app's answer field and should not
inherit from it. Every other field in the app is answering a question; this one is rummaging
through a list, and the pill is the convention for that.

The rows also went from `sm` to `md` padding. At `sm` a 72 pt photograph, two lines of text and a
44 pt disc were touching the card's edge on all four sides.

## D-124 — The quick-add shelf is the head of the same page

The reference draws two lists on the food tab: a shelf of four tiles ("Quick adds") over the full
table. Two lists in a design usually means two requests, and the obvious build is a "popular foods"
endpoint nobody has the data to rank.

They are one list. The tiles are the first four rows of the page the tab already fetches, and the
table below starts at the fifth — no food is drawn twice, nothing is ranked, and the shelf costs no
bandwidth. A search replaces it with its answers: a shelf of unrelated foods above the row somebody
searched for is in the way of the answer.

Row zero of the `ListView` is the headings and the shelf, so they scroll with what they name. A
fixed band above a scrolling list eats a third of a phone's height on the sheet that most needs it.

Not built from the same reference, and why: the filter button beside the search field (it would
duplicate the category control), the "View all" link on the shelf (the whole table is directly
underneath it), and the "Explore recipes" banner (there is no recipes feature to send anyone to).

## D-125 — "All categories" is the food preference, filtered server-side

The reference's category dropdown had nothing behind it. Foods carry `tags`, but those are the
rule pack's namespaced clinical vocabulary (`gi:high`, `attr:root_veg`) — not words to show a user,
and CLAUDE.md rule 4 forbids showing them raw anyway.

`suitableFor` is the vocabulary that already exists for this: the five food preferences of
docs/03 §2, which onboarding asks about in the user's own words. The control reuses that enum and
those l10n labels, so a user who chose "Eggetarian" there reads the same word here.

`GET /foods` takes `suitableFor` and filters in SQL. Not in the client: the list is paged, so a
client-side filter would only ever filter the pages already fetched and the list would change as
the user scrolled. An unknown preference is a 400 rather than an ignored parameter — quietly
returning the whole table to somebody who asked for vegetarian food is the one failure this filter
must not have. Changing the category reloads from offset zero and every subsequent page carries it.

## D-126 — The steps tab is a screen, not a form

Two bare fields and a button on a white sheet. The most important sentence on it — a guessed
calorie figure changes what you are told to eat — was a grey caption under the second field, which
is the least-read position on any screen.

Now: a headline and one line saying what the tab is for, one card per measurement (they ARE two
measurements — the server stores them separately and either can be sent alone), and the warning
promoted to a `HintCard`, which is the component the app already uses for a note that must be read.

Three details, none cosmetic:

- The bounds are named constants. `_maxSteps` sets the bound check, the wheel's top and the caption
  under the field. Three copies of `100000` is how those three drift apart, and a caption promising
  a range the field rejects is worse than no caption. The caption is an ARB `decimalPattern`
  placeholder, so it groups as 100,000 in English and 1,00,000 in Hindi without a second string.
- Both fields gained a wheel (D-95). Someone who read 8,432 off a watch types it; someone logging
  "about six thousand" spins to it. The notch is 500 steps and 50 kcal — a step-of-one wheel for
  100,000 is a wheel nobody can reach the end of.
- The art is the reference's own walker, `assets/activity/walking.png`. Supplied at 1536 px with
  two thirds of the canvas empty and 871 KB on disk: trimmed to its content, re-encoded to 520 px —
  three times the 165 pt ceiling it is ever drawn at — and palette-quantised to 33 KB. It takes its
  SHARE of the row's width (D-111's `heroArtFraction`/`heroArtMax`), not a size invented here.

Still not a calculator (D-80): nothing here turns steps into calories.

## D-127 — The weight form is the screen the reference draws, and it is one form

The Weight tab was a title, a field and a Save button. The reference draws a card: the figure large
and centred, a ruler under it, the unit as a choice, when it was taken, and a note about weighing
consistently.

Built into `LogWeightForm` rather than into the tab, because that form is ALSO the Progress tab's
bottom sheet (D-87). One place still knows the suspect rule, the server's message and the reload.
Only the hero — headline, sentence, scales — lives in the tab: a bottom sheet that opens with a
hero has spent half its height before the field.

**kg and lb.** The server's `weight` kind is bounded in kilograms and refuses any other unit, so
pounds are a way of READING the number and never a wire value. `WeightUnit` converts by the 1959
definition (0.45359237 exactly) in `core/format/`, with a test, because a pound figure sent as
kilograms is a 2.2× error in somebody's plan. Switching units converts the reading rather than
relabelling it: 70.5 kg becomes 155.4 lb.

**The ruler.** `RulerSlider` spans the whole range the server accepts — 20 to 300 kg. It first
shipped as a five-kilogram WINDOW around the last reading, on the argument that the field is there
for a figure read off a scale and the ruler is only for the last two tenths. That was wrong in the
plainest way: a ruler that opens at 34 kg and stops at 39 cannot answer the question somebody came
with, and no amount of dragging tells them why. The window is gone.

Spanning it costs 2,800 notches, so the ticks are BUILT LAZILY, one per slot, rather than painted
onto a single 25,000 pt canvas no phone should be asked to hold — about forty exist at a time. A
notch is a tenth and a labelled tick is a whole unit, at 70 pt per kilogram, which is the reference's
own spacing. And the ruler never announces its own layout: a jump fires the same notifications a
drag does, and answering one is a `setState` during the parent's build.

**When.** `POST /measurements` already took `recorded_at` and the client never sent it. It does now,
for the weight taken this morning and logged tonight. Null still means now, and null is still what
is sent — the SERVER derives the diary day either way (CLAUDE.md rule 8).

**The field stays empty.** The reference shows 70.5 already in the box. The ruler opens on the last
weight the server has, because the next one is nearly always within a kilogram of it — but the field
does not, and Save stays disabled until somebody enters something. A prefilled figure plus a Save
button is a way to log a stale weight without noticing.

## D-128 — A diary you cannot look back at is a display, not a tracker

Two halves of the same defect, both found by asking what "track my progress" needs that the app did
not do.

**Yesterday was unreachable.** `GET /logs/day` has always taken a `date`; the client never sent one.
So everything logged before 04:00 this morning fell off the screen at the boundary and could not be
read again anywhere in the app. Home now carries the day it is showing and the way to the ones
before it, back ninety days.

The arrows say "the day before this one", never a date the client worked out — the server owns where
a day begins (rule 8), and today is still sent as NO date rather than as today's date spelled out.
Two consequences that had to be handled rather than discovered later: the pedometer sync only runs
on today, because copying the phone's count into a past day would overwrite history the user cannot
see changing; and a past day says so on screen, because the `+` sheet writes to today wherever the
user is standing.

**The daily habits had no history at all.** Steps, water and calories burned are measurement kinds —
one row per kind per diary day, with a history endpoint already serving them — and the only place
they appeared was Home, for today. Progress now shows each with its latest reading and the last week
as bars.

Bars, not a curve: a step count resets at the diary boundary, so a line between two of them draws a
value at 3 pm that nobody measured. Weight exists continuously, which is why weight keeps the curve.
The tallest day in the week sets the scale — an absolute one would draw a 6,000-step day as a sliver
under the 100,000 ceiling. A day with a reading always gets a visible bar; a day without gets none,
because nought steps and no answer are different claims and only one of them is the user's.

## D-129 — The water tab, and the two controls the reference draws that the app must not have

Rebuilt to the reference: the day's total in a ring against the goal, the bottle beside it, three
quick-add tiles, today's row, and a note about drinking little and often.

Two things in that reference are deliberately absent.

**No pencil beside the goal.** The reference lets the user edit their daily target. The goal is the
engine's — body weight against the rule pack's `ml_per_kg`, with a floor and a ceiling — and a goal
the app let somebody edit would be the app setting a target (CLAUDE.md rule 2). It arrives with the
plan, and until there is a plan the screen says so rather than inventing a number.

**No list of sips.** The reference draws "Today's log" as a list of separate additions. Water is one
measurement row per diary day that this screen adds to (D-86), so separate entries do not exist on
the server — a list of them would be a history the app made up, and one that would vanish the moment
the sheet was reopened. Today's row is the day's total, and "View history" leaves the sheet for the
week of bars on Progress (D-128) rather than opening a second history inside a modal.

`+250 ml` still writes the running TOTAL, not the glass. That is the whole reason the undo exists,
and it is why the button says what it adds while the write says what the day now holds.

## D-130 — The plan screen, and the subscription it does not sell

Rebuilt to the reference: the day's target with a ring showing how much of it today has used, the
four macros as eaten-against-target, fibre and water beside them, one card per meal slot with its
share of the day, and the suggested foods behind a count rather than a label.

**Two targets the server had been sending all along.** The engine returns `fibreG` and `waterMl` in
`plan.targets` next to the four macros. The client parsed four of the nine numbers and dropped the
rest, so the tab has been drawing an incomplete plan since it was written. No backend change — the
data was already on the wire.

**Fibre is a target with no figure beside it.** A food log row copies kcal and three macros and
nothing else, so what anybody has eaten in fibre is not a number this app holds. "0 / 30 g" would be
a lie of arithmetic. Showing it needs a column on `food_log`, a migration, and the import path to
carry `fibreG` — a slice of backend work, not a widget.

**The eaten figures come from Home's diary, never from anything added up here.** A screen that
summed its own totals would be a second answer to a question the server answers (rule 2). With no
diary in memory the card states the targets and draws no ring: a ring at zero says "you have eaten
nothing", which is a claim rather than a blank (D-43).

**No "Go Premium".** The reference sells a subscription from this screen twice — a pill in the
header and a banner at the foot, with a seven-day trial and four features named. Entitlements are
the server's (rule 3) and the app has no entitlement in it at all: no subscription state, no paywall,
no payment SDK, and docs/11's proration and RBI AFA rules unimplemented on this side. A button that
takes money for something nothing can unlock is the one thing worse than a missing button. It is an
epic — `GET /profile` entitlement or a subscription endpoint, a paywall screen, the payment SDK, and
restore-purchase — and it is listed as one rather than mocked here.

The advice card stays, worded to docs/05 §6: a note about most days beating perfect days, never a
streak, never a score, and never a sentence about the person reading it.

## D-131 — The sign-in art is the reference's own

`assets/welcome/login_hero.png` now holds the reference illustration — the phone with a code, the
padlock, the leaves — replacing the stand-in that D-109 described in the same words.

Same treatment as every other hero in this app: trimmed to its content (the supplied PNG carried a
transparent margin), re-encoded to 520 px — three times the 165 pt ceiling `heroArtMax` ever draws
it at — and palette-quantised. 1.0 MB to 32 KB.

Installed at the SAME path, so `AppAssets.loginHero` and the sign-in page are untouched. The old
file was untracked by git, so it was copied aside before being overwritten rather than trusting a
checkout to bring it back.

## D-132 — The plan card had no hierarchy, and the reference's own photograph was sitting unused

The first build of D-130 was correct and drab: a beige card, olive bars, grey percentages, no
picture. Everything on it had the same weight, which is what makes a screen read as unfinished even
when every number on it is right.

Three changes, all inside the existing tokens:

- **The headline figure sits on the brand green**, white on `AppColors.primary`, with the ring in
  `accentBright` beside it. The macros stay on white below. A card with two surfaces has a top and a
  body; a card with one has a list.
- **One colour per macro** — `macroProtein`, `macroCarb`, `macroFat`, the same three the rings on
  Home already use, now on the disc and the bar. A macro that is orange in one place and green in
  another is three macros to the eye, so `MacroBar` took a `color` rather than each screen inventing
  one.
- **The bowl** (`assets/requirement_screens_img/req1.png`, supplied with the reference and until now
  unused) overlaps the card's top-right corner. It breaks the card's edge on purpose: a photograph
  boxed inside a rounded rectangle reads as a thumbnail. The header carries right padding equal to
  part of the art's width, which is what keeps "1500 kcal" out from under it at 200 % text scale —
  asserted by a test rather than eyeballed.

A photograph, not an illustration, and quantised at 160 colours rather than 128: food has gradients
that flat art does not, and the extra 30 KB is the difference between a bowl and a poster of one.

## D-133 — Three defects the screenshots caught that the tests could not

D-132 shipped a card that looked right in a widget test and wrong on a phone. All three failures are
the same kind: nothing asserts what a screen FEELS like at 390 pt with real data on it.

**The photograph was drawn on top of the percentage.** The header reserved 55 % of the art's width
as right padding and the art was 42 % of the card — so the bowl covered the ring, and "12 % of
today's target" was unreadable behind a tomato. The lane is now the art's FULL width plus a gap, and
the art is capped at 116 pt. The rule it broke is older than the design: when decoration and data
want the same box, the data keeps it.

**The card ate the screen.** `MacroBar` carries its own vertical rhythm and each row added another
`sm` on top of it, the discs were the 44 pt interactive size for something nothing taps, and the
tiles had `md` padding. Three rows plus two tiles came to more than a phone's height minus the
header, so "Today's meals" — the reason the tab exists — was below the fold on first paint.

**"Today's meals" was printed twice**, once as the tab's subtitle and once as the section heading
above the meals. The subtitle now says what the tab is; the heading says what the list is.

And the meal cards themselves: the collapsed card is now ONE row — slot, share of the day, calories.
The macros and the food strip live behind the tap, in the same expansion, instead of a card that
stacked three rows and a second chevron of its own whether or not anyone had opened it. Four of
those was a screen of things nobody had asked to see.

## D-134 — The Plan screen's last mile, and the backend map behind the rest

UI: the first meal slot opens ready — the tab's job is "here is what to eat next", and a column of
uniformly closed rows answers "what are my numbers" instead. One open, the rest a tap away. "View
full day" goes to Home, because Home IS the full day; a second full-day screen inside this tab would
be the same rows in a third place.

Backend, mapped by four parallel readers and checked by two adversarial passes (run wf_8c889147-cfa):

**S1 — fibre eaten (small, ready).** Nullable `fibreG numeric(6,1)` on `food_log` (expand-only),
copy `food.fibreG × factor` at log time, sum into day totals with null-as-0 — old days under-report
and say so by being old, and no flag splits the totals contract across client and server. The
TARGET side is already computed (`computeFibre`, pack `g_per_1000_kcal`) and persisted in
`plan.targets`; `logs.service` simply never mapped it into `DayView.targets` — one line. No logs
spec exists at all; the slice adds one.

**S2 — real meals (medium).** `meals: []` is hardcoded because engine steps 11/13/14 were never
written. PROJECT-STATE's "blocked, needs food DB" is STALE — 281 foods exist. What remains: pool
builder (translating `allergen:*`→`food.allergens`, `group:*`→`suitableFor`, since the food tag
vocabulary forbids those prefixes), greedy fill + repair with every constant read from the rule pack
(`fill_max_iterations`, `household_increments`, tolerances — rule 1), alternates whose ±10 %/±5 g
window must be ADDED to the pack before the code exists, EngineInput/Output contract changes with
the food pool passed IN (purity, rule 2), the existing seeded PRNG (never Math.random), a `meals`
jsonb column + migration, and persistence. Data debt that will make specific overrides silently
vacuous: 12 rule-pack tags appear in zero seed rows; prep-time and may_contain have no schema.

**S3 — Go Premium (large).** Entitlements ALREADY exist server-side — `GET /v1/billing/entitlements`,
tier FREE/BASIC/PRO with a typed capability map — but nothing ever writes a subscription row, so
every user is FREE forever. The whole purchase path is missing: checkout/verify/cancel/upgrade,
Razorpay (SDK installed, never imported, keys blank), both webhooks, the §5 lifecycle, the
phone_hash trial ledger with its mandatory 48 h reminder, integer-paise proration, `requires_afa`.
Two live inconsistencies to fix before any client keys off them: the 403-vs-422 ENTITLEMENT_REQUIRED
split (`require()` has zero callers), and entitlements specced on `/auth/me` but shipped only on
`/billing/entitlements` — pick one, update docs/09. Two shipped prices await pricing sign-off, a
launch gate for any screen that displays them. Client side is entirely unbuilt, down to the unused
`isEntitlementRequired` hook.

## D-135 — What two screenshots said that fourteen green tests could not

The user compared the built Plan tab against the reference and called it out, correctly. The list,
and what each fix was:

- **The ring did not render.** `ProgressRing`'s light-theme default paints fill AND track in
  `colorScheme.primary` — the deep brand green — and D-132 had put it on a header of exactly that
  colour. Invisible by construction, and no test could see it because tests find widgets, not
  contrast. The ring took `color`/`trackColor` overrides; the header passes `accentBright` and a
  quarter-strength track; a regression test now asserts the header ring never carries the header's
  own colour.
- **The bowl went beside the card, not on it.** Third arrangement in three rounds: on the corner it
  covered the ring (D-133); with a reserved lane it squeezed "Recommended for you" onto two lines.
  The reference had it right all along — the card takes its column, the photograph takes its own,
  and below `heroBreakpoint` the art column is dropped entirely for rule 12.
- **The fibre/water tiles out-shouted the macros.** Outlined white boxes gave the footnotes more
  weight than the rows they footnote. Now a quiet tint, no border.
- **The meal-row subtitle wrapped in every card.** Two facts on one small line — the share and the
  suggestion count. One fact stays; the count moved into the expanded detail beside the macros,
  which is where the reference shows it.
- **The server's safety warning rendered as a bare white rectangle** between two finished cards,
  reading as a fault. The text is the server's, verbatim (rule 7); the chrome is ours — it is a
  `HintCard` now.

The lesson worth the entry: every one of these passed `flutter analyze` and the full widget-test
suite. Layout collisions, invisible-by-colour, visual weight, and wrapping are screenshot-class
defects — the loop that catches them is a person running the app, and this project's tests should
be read as necessary, never as sufficient, for a screen's quality.

## D-136 — The new Plan reference, built to the data instead of past it

A second reference for the Plan tab: pale target card with ring, bowl and a consumed/left bar; the
macros as three coloured TILES; fibre and water with eaten-against-target; premium surfaces top and
bottom; a photograph on every meal row; and a seven-day streak card.

**Fibre eaten is real now — the backend slice shipped with it** (planned in D-134 as S1): nullable
`fibreG` on `food_log` (expand-only migration), `food.fibreG × factor` copied at log time, null on
custom entries because nobody types their fibre, null-as-nothing in the day totals, and the fibre
TARGET the plan always carried finally mapped into `DayView.targets` — the one-line omission that
had kept "25 / 30 g" impossible. Three new specs run the real reducer; 151 API tests green.

**The premium surfaces are server-gated, not decorative.** The app grew its first billing client —
`GET /billing/entitlements` and `GET /billing/prices`, the two endpoints that exist (D-134) — and
the pill and banner render ONLY once the server says the account is FREE. Unknown, loading, failed,
or any paid tier: no sales pitch, because docs/11 §10 names "upgrade CTA while subscribed" as a
shipped defect of the old build and a network blip must not flash a banner at a paying customer.
The banner's feature list is the REAL tier gap from the server's own entitlement map —
regenerations, alternates, PDF export, priority support — never a promise the backend cannot keep.
Tapping opens the price sheet: the server's live matrix, integer paise formatted the Indian way,
and a plain note that payments open soon — no pay button that goes nowhere. Checkout itself stays
the D-134 S3 epic.

**The streak card is not built, and will not be.** docs/05 §6 and CLAUDE.md's tone rules exist
precisely for it: no streaks, no red missed-days, no notification implying failure. A seven-check
row is a streak with a calendar attached, and the week it breaks it becomes the "you failed"
banner the tone rules forbid. The advice card keeps that slot.

Meal rows carry the first suggested dish's photograph — a plate the user can actually be offered,
rather than the reference's stock one — and the macro line in the three macro colours. The ring
sits on the pale tint its defaults were measured for; D-135's override stays for any future dark
ground.

## D-137 — Two paragraphs, two different owners, one fix

The user pointed at the Plan tab's mid-section: a two-line titled advice card and a six-line target
note, a screen of prose between the numbers and the meals. Right — but the two texts have different
owners, so they get different treatment.

**The advice card is ours, so it shrank to what it earns:** one line, no heading — "Miss a meal?
The next one is the one that counts." A titled paragraph of encouragement on a screen of numbers is
the thing being scrolled past, not read.

**The target note is the server's safety copy** — rule 7, verbatim, every word stays. What is ours
is the PRESENTATION, so `HintCard` grew a `dense` form: note-size type, tighter padding, smaller
disc. The message is unchanged; its footprint on the screen is roughly halved. Deliberately NOT an
expander — a safety sentence behind a "read more" is a safety sentence unread, which is the same
docs/05 instinct that keeps safety copy outside paywalls.

## D-138 — Home rebuilt to the dashboard reference, on the walker's stage

The Home tab now reads top to bottom the way the reference does: calorie summary on the brand
green (supplied large, burned as a ringed figure or an em dash — never a zero, D-50), the water
card layered over its foot, the four nutrients as tiles with their own rings — fibre included, now
that the day carries a fibre sum (D-136) — the streak, the plan's meals with the first suggested
dish as each row's photograph, and a celebration card on the day every target is met.

**The walker stays, and the reference's static mascot does not replace him.** The user's own
instruction: the supplied stage art becomes the BACKGROUND of the walking animation. `_Stage`
positions the podium's surface — 86 % of the way down the art — exactly under his feet, asking
`WalkingMan` where he stands rather than re-deriving it (D-63's lesson). The image carries an
explicit height: sized only by width it is 0 pt tall until the asset decodes, and everything
measured against the podium line jumps a frame later. The macro floor-rings the stage replaces had
carried the macros; those now live in the tiles.

**The streak is a LOGGING streak, built inside the tone rules' letter.** docs/05 §6 bans streaks on
WEIGHT, red missed-markers, and failure banners. This one counts days with anything logged; an
unlogged day is a hollow circle, never a red mark or the word "missed"; and at zero the card is
simply absent — "0 day streak" is the failure banner the rules exist to prevent. Its data is the
three measurement histories plus today's diary; past food-only days are invisible to it until a
server "days logged" endpoint exists, and a day the streak cannot see renders neutrally, which is
the safe direction to be wrong in. ponytail: measurement-kinds only, add the endpoint when it lies.

**"You hit today's targets" appears only on the day it is true** — every server ratio at or past
its goal. There is no card for the other days: docs/05 bans the failure banner, not the
celebration. ponytail: met is ratio >= 1; a "within 5 %" band would be the app inventing a
threshold, which is rule-2 territory.

The premium pill rides the Home heading through the same server-gated `PremiumPill` the Plan tab
uses — extracted to `features/billing/premium_widgets.dart` so the gate cannot fork. The old
seven-row stat list, the rings legend, and the "aren't counted unless" caption are gone; the steps
row alone survives, because rule 10's source label has nowhere else to live on this screen.

## D-139 — The walker gets small, and his stage becomes the shell's

Two live screenshots, two defects, one root cause each.

**He was a giant.** The Home anchor's 0.52 height factor dates from when he WAS the screen — the
old hero built the whole tab around him. On the rebuilt dashboard (D-138) half a phone of cartoon
was standing on the calorie card, and because the shell's walker never scrolls, he trampled the
nutrient tiles the moment the page moved. He is 0.28 now, high and right, above the content he
used to cover. The You anchor is untouched — the profile frame is a setting sized around him.

**The podium was off his feet.** D-138 drew the stage from the PAGE's layout box while the shell
places the walker against its own — two coordinate spaces that agree in a test harness and differ
on a phone by exactly the safe areas. That is the D-63 failure, third appearance, and the fix is
D-63's fix: the stage moved into the shell and is drawn from the SAME `boundsAt` call that places
him, sized against HIS height so shrinking him shrinks his setting. It fades with his travel so it
never hangs in the air over Plan or Progress, and `shell_walker_test` pins podium-to-feet at
±0.5 pt in the one coordinate space that now exists.

## D-140 — Today's meals shows what was eaten, and the walker moves behind the page

Three changes from one screenshot review.

**The meals section was the wrong tense.** It showed the plan's prescription — kcal a slot SHOULD
carry — on the tab whose job is what the day actually held. The prescription lives on the Plan tab;
Home's "Today's meals" is now the diary grouped by slot, each slot headed by its own eaten sums:
kcal, and P/C/F in the app's macro colours. The per-entry macros had been on the wire the whole
time (`toView` sends protein_g/carb_g/fat_g per entry); the client just never parsed them. The
plan-meals fetch, the slot thumbnails and their controller state are gone with the section.

**The gap was a reservation for a walker who no longer needs one.** The hero held `max(320, his
floor)` of vertical space open to keep content out from under him. With him behind the page that
reservation was a screen of empty cream, and it is deleted — the hero is its content's height.

**He walks BEHIND the cards now, by the user's own call.** The shell's stack order became stage →
walker → page: the pages paint no background of their own, so he shows wherever a page has
nothing, and the moment it scrolls its cards pass over him instead of being trampled. The You
sheet still covers him and its hole still reveals him — that relationship never depended on the
page layer's position.

## D-141 — Home restyled to the new reference mock

A screenshot-to-screenshot comparison against the current Home mock; every visible mismatch is a
deliberate change here, in one pass.

**Inter replaces Montserrat (supersedes D-119).** D-119 matched the old `lib/screen` build; the
mock this Home now answers to is set in a neutral grotesque. One line in `AppTextStyles`.

**The page cooled down (supersedes D-58's cream).** `lightBackground` FAF5EF → F7F6F2: next to
the mock the warm cream read peach. Lighter, so every text ratio only improved.

**The calorie card is the mock's card.** Top-left-lit gradient (`primary` → new `primaryDeep`),
the figure huge with the unit small beside it (they are two Texts now — tests find '348', not
'348 kcal'), a hairline seam between supplied and the burned ring, and 'kcal' captioned inside
the ring under the number.

**Nutrient tiles: solid disc, white glyph, ink figure, no border.** The tinted disc read as a
smudge, the coloured figure competed with the ring, and the warm outline was the loudest thing in
the row — the disc and ring carry the macro's identity, the number stays a number.

**The streak card is one line.** Words left, week right (a Wrap, so 200 % text stacks instead of
clipping). A day chip is the LETTER in a circle with a green check badge hung under it when
logged; today-logged is a gold disc with a star. Not-logged stays the neutral hollow circle —
docs/05 §6 unchanged.

**Chrome:** the wave is the emoji's gold, not teal (the emoji itself stays banned); Go Premium is
the quiet green tint, not a gold banner; the FAB is the brand green in light mode (dark keeps the
accent for contrast); Details grew its chevron.

**Not matched, on purpose:** the day bar stays (D-128 — the mock has no route to yesterday); the
walker stays the 2D frame sequence on his stage (the mock's 3D character is an asset we do not
have); the mock's meal-row cards with photos and per-meal progress bars are a separate piece of
work.

## D-142 — Home's gaps closed and the meal rows became the mock's cards

**Two dead bands deleted.** The ListView's top inset (the day bar now sits straight under the
heading) and the spacer between the hero and the Macronutrients heading — the water card's upward
overlap already leaves its translate's worth of air, and the heading's button height does the
rest. The no-plan branch keeps its own spacer before the Create-plan button.

**A slot is a card now.** `_SlotSummary` renders the mock's meal card: the slot's tinted disc in
its own hue (amber dawn, coral café, green noon, purple snack, blue night — identity, never
judgement), the name, "{pct}% of your day" (new l10n key `homeSlotShare`, en + hi), the macro
line, and on the right the kcal sum over a share bar whose BAR clamps while the number does not —
the water card's own rule. Share and bar exist only when the server set a kcal target; a share of
an invented target would be rule-2 territory. The chevron goes somewhere real: the card opens the
log sheet. Entry rows still follow underneath — they carry the household measure.

**No photo on the card, on purpose.** The mock shows a food thumbnail per meal; `LogEntry`
carries no image on the wire. When the API sends one, `FoodImage` is the widget waiting for it.

## D-143 — Progress became the mock's dashboard, honestly fed

The reference Progress mock, rebuilt on today's API with every gap either filled honestly or
written down in `docs/21-progress-dashboard-backend.md` rather than faked.

**The data is two weeks of diary days, anchored on the server's today.** `ProgressController`
asks for today (the server NAMES the anchor date, rule 8), then the 13 days before it in
parallel, and averages fed days only — display arithmetic over server sums, never a target of its
own. Fourteen GETs is the wrong shape and doc 21 §1 names the summary endpoint that retires it.

**What the mock got:** the section chips (Overview · Nutrition · Weight · Activity · Habits) as a
client-side filter; the This week / Last week pill; the calorie card — average, goal, %-of-goal
ring, vs-last-week line, and seven bars under a dashed goal line; the macro balance card with
tinted %-chips; the weight card merged into one (current weight left, dotted trend line with a
soft fill right, See all); the 7-day consistency card on the shared DayDot chips (extracted to
`core/widgets/day_dot.dart` from Home's streak card).

**What the mock did NOT get, on purpose:** amber figures on under-goal days (a colour judgement,
docs/05 §6 — every figure keeps its ink); an Achievements card (server must award achievements,
and a weight-loss badge needs clinical sign-off first — doc 21 §4); "vs last 30 days" on weight
(the server's change figure is since-start; doc 21 §3); any card at all when its data is absent —
no diary registered, no dashboard, and a week with nothing to average claims no comparison.

Tests: the existing weight/habit/tone tests unchanged (the dashboard hides without a diary), a
new dashboard group pins the average-vs-goal ring, the chip filtering, and that a dataless last
week claims no change.

## D-144 — The You tab became the mock's Profile screen

**The frame greets instead of stating an age.** The hole and the walker stay (D-59/D-70); beside
them now sit the avatar with its photo control, "Hi, {name}!" (no name → no invented one), and the
warm line. Age moved to the details card, where it already lived.

**Today at a glance, in miniature.** A card fed by today's diary (optional dependency, the D-99
pattern): calories against the goal with a %-ring, the three macros and water as small bars, and
the phone's step count when the day carries one. "See all" goes Home.

**Goal rows went white.** D-61's saturated bands became the mock's rows — the macro's colour on a
solid disc and on today's progress bar, the target in ink. A water goal row appears when the diary
carries a water target. Deliberately NO "Edit goals" and no "Add more goals": targets are the
server's answer to the profile (rule 2).

**Body stats is the one honest stat.** Latest weight plus the server's change sentence. The mock's
BMI/Body Fat/Muscle Mass tiles — and their "Normal/Healthy/Good" chips — are not built: the data
does not exist server-side, the client may not compute a BMI (rule 2), and a judgement chip on a
body is docs/05 §6's own example. docs/21 §7 records what the server would have to send.

**Quick actions go somewhere that exists.** Edit profile (the existing sheet), My plan, Reports.
No Reminders pill — there are no reminders to manage. The page heads itself "Profile"; the TAB
stays "You" (docs/14 §1 owns the shell's names).

## D-145 — The You sheet's hole frames the walker again, and only him

**Home was showing through the frame.** D-140 put the walker BEHIND the pages, so the page the
shell kept mounted under the You sheet — Home — painted its calorie card over him, and the hole
framed that card instead of his face. The fix is one condition: once the You sheet is fully in
place the behind page unmounts; during the slide it stays, because the sheet has not covered it
yet. The hole now reveals stage, walker, page ground — nothing else.

**The frame band came down to its content.** `AppSizes.profileFrame` 320 → 240: the floor was
sized for the old 84 pt age figure and held a dead band open between the hole and the glance card.

**The photo affordance is the mock's camera badge** on the avatar's corner, not a "Change photo"
caption under it. The avatar stays the button; the badge is decoration. And the demo profile's
name is now a name — "We're", a slip of onboarding, greeted the user as "Hi, We're!".

## D-146 — The Profile hero matched to the mock's row

Three buildable gaps from the side-by-side audit, closed: the greeting sits BESIDE the avatar
(a row, not a stack); an Age · Height strip with icons and a divider sits under the hero — age
and height left the details card so one screen does not print the same fact twice ("Member
since" still waits on `created_at`, docs/21 §7); and today's step count is the mock's white
pill hung at the walker's feet in the frame band, not a caption inside the glance card. Still
not matched, knowingly: the settings gear (no destination exists) and the walker's foliage
scenery (no art asset).

## D-147 — The Profile hero's geometry, corrected against the render

The first D-146 build looked wrong on the phone and each fault traced to geometry, not styling.
**The greeting wrapped** because the walker's circle took half the hero: the You anchor moved to
the right edge and shrank (0.46/0.5 → 0.85/0.42), the hole came down with him
(`profileFrameHole` 0.33 → 0.26 — his head still clears the rim), and the frame band widened to
0.52 of the page. **The stat strip printed into the circle** because the frame band's height was
computed from `bodyHeight - list.maxHeight` — a figure that silently included the sign-out
button and FAB clearance pinned BELOW the list, so the band ended ~96 pt above the circle's
bottom. The button lives inside the list now (at its foot, where the mock has it anyway), the
subtraction is honest, and the strip clears the frame.

## D-148 — The floating greeting was a `mainAxisSize` bug, and the hero got the mock's proportions

The render after D-147 still showed the avatar at the top with the greeting floating far below
it. The cause was not layout intent: `ProfilePhoto`'s internal Column defaulted to
`mainAxisSize.max`, took every point of height its new Row offered, and top-pinned the avatar
while the text column centred. One `mainAxisSize.min` fixes it — avatar and greeting now sit as
one row.

With that real bug gone, the hero took the mock's proportions: the walker up into the top-right
corner beside the heading (You anchor 0.85/−0.68, heightFactor 0.3), the hole down to 0.22 of
the width, the frame band floor down to 150 (it only holds the avatar row now), and the greeting
block out to 0.58 of the page.

## D-149 — The walker's stage stands behind him on You too

The "missing scenery" gap on the Profile hero was never a missing asset: `dashboard_stage.png`
IS the mock's backdrop — the pale arch, the leaves, the podium — and Home has drawn it behind
the walker since D-138. The stage renderer just had Home spelled into it. It now takes the tab,
renders for both walker tabs, and the You frame's circle shows him standing in the same setting
the mock draws — fading with his travel exactly as on Home, positioned off his own bounds so the
podium stays under his feet at the smaller D-148 size.

## D-150 — The frame's hole became the mock's oval

A circle could not hold the walker: wide enough for his height it swallowed the hero (the D-146
problem), narrow enough for the hero it cropped him at the shins (the render after D-148). The
mock's blob is taller than wide, and now so is the hole: `FramePainter` cuts an oval — half-width
from the page (`profileFrameHole` 0.19), half-height from the walker himself
(`profileFrameHoleHeight` 0.62 of his height) — centred on the figure, so the whole of him stands
inside with air above and below. He also stepped in from the screen edge (anchor x 0.85 → 0.72),
which had been clipping the rim flat.

## D-151 — The hero is three corners, not a column

What every earlier pass missed about the mock (ui-ux-pro-max review): the hero's LEFT half lays
out independently of the oval beside it. The band is now a Stack of three positioned corners —
avatar row pinned to the top straight under the subtitle, the Age · Height strip pinned to the
foot beside the oval's lower third, the step pill on the frame's lower-right edge — instead of a
column that vertically centred the greeting and made the strip queue below the whole oval. The
walker also rose to −0.72 so the oval's crown reaches the title line, the mock's own placement.

## D-152 — The You tab shows the walker exactly as Home does: no sheet, no hole

By the user's own call. The oval hole was the wrong reading of the mock all along: the "blob"
behind the walker is not a cut-out in the page — it is the stage art itself (`dashboard_stage`'s
pale arch), free-standing, and Home has always shown it that way. The You page now works like
Home: it paints no full-bleed sheet, the hero band simply leaves room where the shell's walker
and his stage show through, and the cards pass OVER him when the list scrolls. `FramePainter`
and the hole tokens are deleted; the hero band's height keys off the walker's own bounds. The
D-151 three-corner Stack (avatar top-left, strip bottom-left, step pill bottom-right) carries on
unchanged around him.

## D-153 — The red-line audit: dead bands squeezed out of Profile

Four oversized gaps the user marked in red, each with its own cause. The hero's empty middle:
the walker rode too low and large, so the band stretched — he rose and shrank (anchor −0.8,
heightFactor 0.25) and the band now ends at his feet, not a spacer past them. Strip→glance and
card→goals: `lg` spacers stacked onto `SectionHeader`'s xl top padding; the spacers are gone and
the header's own padding came down to lg/xs — a GLOBAL rhythm change, made once in the shared
widget, since the trailing TextButton's 48 pt floor already pads every header row.

## D-154 — The way to You fades the page it leaves

The flicker on Home/Plan/Progress → You was D-152's one loose end: the You page used to be an
opaque sheet that COVERED the outgoing page as it slid down (D-71's whole design), and when the
sheet went transparent the outgoing page just sat there under the slide and then popped away in
one frame at D-145's unmount. The outgoing page now fades in step with the slide
(`Opacity(1 − youIn)`), so it has a real exit; leaving You, the same fade runs backwards as the
arriving page fades in under the departing sheet. At rest no page carries the Opacity — the
shell's settled-page rule holds.

## D-155 — Section rhythm settled at the button's floor

The second red-line audit marked the card→header gaps that survived D-153. All three were the
same number: `SectionHeader`'s top padding, stacked on the ~11 pt of visual air its 48 pt action
button already carries. Top padding came down to sm — the section rhythm is now the button's
floor plus a sliver, made once in the shared widget for every screen.

## D-156 — Every section header stands the same height

The "congested here, airy there" complaint had one cause: a header WITH an action was 48 pt tall
(the button's floor) while one without collapsed to bare text, so identical seams rendered
differently depending on nothing but whether an Edit button happened to exist. `SectionHeader`
now holds the 48 pt floor with or without an action — one row height, one seam, everywhere.

## D-157 — The calorie card slimmed, and its ring learned geometry

"Make it thin": padding lg→md, the supplied figure down one type step, the burned ring 76→64.
The first slim pass exposed a real bug: the ring's contents were fitted to its full DIAMETER,
so "4,000" ran stroke to stroke and read as spilling out. The number now inscribes in the ring's
INNER circle (`_ringInner`, the inscribed square's side) — and only the number: the unit already
stands beside the supplied figure, and "burned" captions the ring below. The water card the user
had already slimmed by hand stays exactly as they left it.

## D-158 — "Down" while the chart rises: the windowed change shipped, and the readings got a report

The user logged a jump and the weight card still said "0.8 kg down since you started tracking" —
honest arithmetic, wrong window. docs/21 §3's `change_30d` is now implemented end to end:
`windowedTrendChange` in the API (same moving-average discipline, last 30 diary days, null when
the window holds no trend; 3 new rule specs), parsed on the entity, and preferred by BOTH weight
sentences (Progress trend card and Profile body stats), which fall back to the since-start line
when the window is silent.

And the "how does a user see the full report, date-wise" half: the Progress weight section — the
trend card's See all leads there — now carries a History card: every reading newest first with
its date, its source (rule 10), and the value; a suspect reading is shown with the neutral "left
out of the trend" note, never hidden and never red (docs/08, docs/05 §6).
