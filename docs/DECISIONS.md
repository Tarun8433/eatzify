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
