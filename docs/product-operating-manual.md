# CLAUDE.md — Eatzify

Operating manual for AI coding sessions on this repo. Read fully before the first edit of a session.

## 1. What this product is

Eatzify is an Indian-market diet, nutrition and habit-tracking platform. Three surfaces:
- **User app** (Flutter, Android + iOS) — onboarding, diet plan, food/water/step/weight logging, progress.
- **Coach app** (same Flutter binary, role-gated) — assigned clients, check-ins, messaging.
- **Admin panel** (Flutter web build or React; see ADR-006) — users, coaches, tickets, nutrition DB, notifications.

Backend: NestJS (TypeScript) REST API + PostgreSQL + Redis, deployed on a Hostinger VPS behind Nginx.

## 2. Hard rules — violating any of these is a rejected change

1. **No nutrition constant in code.** Every calorie/macro/threshold number lives in a versioned rule
   pack (`config/rule-packs/*.yaml`) loaded at boot. If you need a number, add it to the rule pack and
   reference it. Grep for a literal like `1.55` or `0.8` in `src/` — there should be zero hits.
2. **The engine is pure and deterministic.** `packages/diet-engine` has no I/O, no clock, no random,
   no DB, no HTTP. Same input + same rule pack version = byte-identical output, forever.
3. **Every plan output carries `rule_pack_version` and an explainability trace.** A plan we cannot
   explain is a plan we cannot defend.
4. **Never write medical claims into UI copy.** Not "cures", not "reverses", not "treats". The approved
   phrasings are in `docs/05-clinical-safety-guardrails.md` §7. Use them verbatim.
5. **No PII in logs.** No email, phone, name, weight, BMI, or condition in any log line, exception
   message, or analytics event. Log `user_id` only. There is a lint rule; do not suppress it.
6. **No health data in URL paths or query strings.** Ever. POST a body.
7. **Migrations are forward-only and reviewed.** No `synchronize: true`. No destructive migration
   without an explicit backup step in the same PR description.
8. **Money is integer paise.** `amount_paise BIGINT`. Never a float, never rupees-as-decimal.
9. **All timestamps are `TIMESTAMPTZ`, stored UTC, rendered `Asia/Kolkata`.** The app has a
   day-boundary problem otherwise (a 00:30 IST food log belongs to the previous day's diary — see
   `docs/03-domain-model.md` §6).
10. **Minors are out of scope.** If DOB implies age < 18, onboarding stops. Do not add a bypass.

## 3. Stack and conventions

**Flutter:** GetX (state + routing + DI) over Clean Architecture, feature-first. Layout per
`docs/14-flutter-app-spec.md`. `Get.lazyPut` in bindings; never construct a controller in a widget.
`Either<Failure, T>` from dartz out of every use case. Immutable entities with `copyWith`.
No hardcoded colors, sizes or strings in widgets — theme, `AppSpacing`, and `l10n` only.

**Backend:** NestJS, module-per-domain. DTO validation with `class-validator` on every endpoint.
Repository pattern; no query builder calls from controllers. TypeORM migrations.

**Naming:** `snake_case` in SQL and JSON, `camelCase` in Dart/TS variables, `PascalCase` for types.
Dart files `snake_case.dart`.

**Git:** Conventional Commits (`feat(engine): …`). Branch `feat/<ticket>-<slug>`. Squash merge.
PR body must state which doc section governs the change.

**Tests:** Engine changes require golden-vector tests. API changes require a contract test.
UI changes require a widget test for loading, error and empty states. Coverage floor: engine 95 %,
billing 90 %, everything else 60 %.

## 4. Ask me first (do not decide alone)

- Adding, removing or renaming a nutrition constant or a medical override rule.
- Anything that widens what a coach or partner can see about a user.
- Anything that changes price, plan entitlements, trial length or refund behaviour.
- Adding a third-party SDK, especially one that touches health data or payments.
- Schema changes to `users`, `health_profiles`, `consents`, `subscriptions`, `commissions`.
- Any copy shown to a user about a medical condition.

## 5. Definition of done

- [ ] Governing doc section cited in the PR.
- [ ] Tests written and passing; golden vectors re-run if the engine was touched.
- [ ] Loading / error / empty states implemented (UI) or error envelope respected (API).
- [ ] No new lint or analyzer warnings. `dart analyze` and `eslint` clean.
- [ ] No PII in logs; no secrets in code; `.env.example` updated if a new var was added.
- [ ] i18n keys added for every new user-visible string (en + hi).
- [ ] Rule pack version bumped and changelog entry added, if constants changed.
- [ ] Doc updated in the same PR if behaviour diverged from the doc.

## 6. Things that are already wrong in the existing build

Do not copy the current prototype's patterns. `docs/15-ux-audit-screenshots.md` lists 31 defects.
The important ones: four different navigation shells, two duplicate admin user screens, foods whose
calories don't match their macros, a weight-change readout showing −30.0 kg for a user who has
logged three inconsistent weights, and a protein target that violates the written spec. When
extending an existing screen, fix the defect listed for it in the same PR or open a follow-up ticket.

## 7. Session start checklist

1. Read this file.
2. Read the governing doc for the task.
3. Restate the task and the constraints you're operating under before writing code.
4. If a constraint blocks the task, stop and say so. Do not route around it.
