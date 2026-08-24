# Eatzify App (Flutter)

Client + coach app for Eatzify. One binary, role-gated at the shell.
Specs live in `docs/` at this repo root. Read the governing doc before implementing.

## Repo layout — monorepo

Flutter is at the root; the backend is a subdirectory. `docs/` is shared by both, so every
`docs/NN-*.md` reference in any rule or skill resolves from here.

| Path | What | Scope |
|---|---|---|
| `lib/` `test/` `android/` `ios/` `web/` | Flutter app | this file governs |
| `api/` | NestJS REST API | `api/CLAUDE.md` governs (nearest file wins) |
| `docs/` | Specs, shared source of truth | read-only in practice; `docs/05` is Edit-denied |
| `.claude/rules/` | Path-scoped — Flutter rules fire on `lib/**`, backend rules on `api/**` | both |

Backend commands and hard rules are in `api/CLAUDE.md`; do not apply Flutter rules to `api/**`.

## Read these before exploring the repo

| File | Answers |
|---|---|
| `docs/PROJECT-STATE.md` | What is built, what is blocked, how to verify it, what is next |
| `docs/DECISIONS.md` | Why anything is the way it is. Append-only, `D-01`..`D-nn` |

Both are cheaper than reading the tree and are kept current. Update them at the end of any session
that changes state or settles a decision — a stale state file is worse than none. `docs/07-adr-log.md`
holds product/architecture ADRs; `DECISIONS.md` holds build-and-tooling decisions and every place the
specs disagree with each other.

## Commands

- Run: `flutter run --flavor dev`
- Analyze: `flutter analyze` · Format: `dart format lib test`
- Test: `flutter test` · single: `flutter test test/path_test.dart`
- Codegen: `dart run build_runner build --delete-conflicting-outputs`
- Build: `flutter build appbundle --flavor prod`

## Stack

GetX (state + routing + DI) over Clean Architecture, layer-first with features nested in
`presentation/features/`. dartz `Either` out of every use case. dio. hive. flutter_screenutil. intl.

Structure: `core/` · `domain/{entities,repositories,usecases}` · `data/{models,datasources,repositories}`
· `presentation/{shell,features,l10n}` · `routes/`. Full tree: `docs/14-flutter-app-spec.md` §2.

## Hard rules

1. **One navigation shell.** Client: `Home · Plan · [+] · Progress · You`. Coach:
   `Clients · Check-ins · [+] · Messages · You`. Adding a tab requires an ADR. The old build had four
   shells and a hamburger menu; do not reintroduce either.
2. **No business logic in widgets.** If a widget computes a BMI, a target, a price or an entitlement,
   it is in the wrong layer. The server decides; the app renders.
3. **Entitlements come from the server.** Never compute one client-side. Handle `403
   ENTITLEMENT_REQUIRED` by showing the upgrade sheet.
4. **Never show a raw enum.** `lose_weight`, `moderate`, `vegetarian` go through l10n before display.
5. **No hardcoded colors, sizes, radii or strings.** Theme tokens, `AppSpacing`, and l10n keys only.
6. **Every data screen implements all four states** via `ViewState<T>`: Loading, Empty, Failed, Ready.
   Never infer state from nulls. No infinite spinners.
7. **`user_message` from the API is the only error text shown to a user.** Do not write your own copy
   for a medical or safety message — those strings are server-controlled by design.
8. **Diary dates come from the server.** Never compute the 04:00 IST day boundary client-side.
9. **No PII in logs or crash reports.** Redact before Sentry.
10. **Health data:** read-only from Health Connect (Android) / HealthKit (iOS) behind
    `HealthDataSource`. Never Google Fit — its APIs shut down at the end of 2026. Manual entry is
    always available as a fallback, and the data source label is always visible.
11. **No localStorage-style ad-hoc persistence.** Hive boxes declared in `core/storage/hive_boxes.dart`.
12. Touch targets >= 48 dp. Contrast >= 4.5:1. Must survive 200 % font scale without clipping.

## Tone rules (non-negotiable — `docs/05` §6)

No judgemental status chips ("Obese"). No red "Missed" markers on past days — use neutral "not
logged". No leaderboards or streaks on weight. No notification implying failure. Safety messages are
never behind a paywall.

## Where the answers are

| Question | Doc |
|---|---|
| Screens, states, IA, folder tree | `docs/14-flutter-app-spec.md` |
| Requirements and acceptance criteria | `docs/02-prd.md` |
| Vocabulary, enums, units, diary day | `docs/03-domain-model.md` |
| Safety copy and tone | `docs/05-clinical-safety-guardrails.md` |
| API contract and error codes | `docs/09-api-spec.md` |
| Known defects in the current build | `docs/15-ux-audit-screenshots.md` |

## Definition of done

Governing doc cited in the PR · all four view states implemented · widget test for each · l10n keys
added (en + hi) · `flutter analyze` clean · no hardcoded values · tested at 200 % font scale and in
dark mode · offline path considered.
