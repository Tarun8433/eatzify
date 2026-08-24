# Eatzify API

NestJS + PostgreSQL + Redis backend for Eatzify (Indian diet & nutrition platform).
Full specifications live in `docs/` at the **monorepo root** (`../docs/` from here). Read the
governing doc before implementing. The Flutter app is at the repo root; see the root `CLAUDE.md`.

## Commands

- Dev: `npm run start:dev`
- Build: `npm run build`
- Test: `npm test` · single file: `npm test -- path/to/file.spec.ts`
- Golden vectors (engine): `npm run test:golden`
- Lint: `npm run lint` · Types: `npm run typecheck`
- Migration: `npm run migration:generate -- -n Name` · `npm run migration:run`
- Seed (dev/staging only): `npm run seed`

## Stack

- NestJS, module-per-domain (`src/modules/*`). TypeORM. Zod/class-validator DTOs.
- `packages/diet-engine` — pure, deterministic, no I/O. `packages/contracts` — shared DTOs/enums.
- BullMQ workers. Redis cache. Deployed on a Hostinger VPS behind Nginx.

## Hard rules

1. No nutrition or clinical constant in code. They live in `config/rule-packs/*.yaml`. Zero numeric
   literals like `1.55` or `0.8` in `src/` or `packages/diet-engine/src/`.
2. The engine is pure: no `Date.now()`, no `Math.random()`, no DB, no HTTP. Seeded PRNG only.
3. Money is integer paise (`BIGINT`). Never a float. Never rupees-as-decimal.
4. Timestamps are `TIMESTAMPTZ` stored UTC. Business-day logic uses `diaryDateFor()` — the 04:00 IST
   diary boundary — and there is exactly one implementation of it.
5. No PII in logs, exceptions or analytics: no name, phone, email, weight, BMI or condition. `user_id` only.
6. No health data in URL paths or query strings. POST a body.
7. Safety floors in `docs/05-clinical-safety-guardrails.md` §2 are enforced server-side on every path,
   including coach overrides. No role bypasses them.
8. Migrations are forward-only and expand/contract compatible. No `synchronize: true`.
9. Every endpoint returning a health field gets the audit interceptor and a `docs/10` matrix test.
10. Onboarding rejects users under 18. There is a DB `CHECK` constraint too. Do not add a bypass.

## Where the answers are

| Question | Doc |
|---|---|
| Calorie/macro math, overrides, meal split | `docs/04-diet-engine-spec.md` |
| Floors, gates, approved user-facing copy | `docs/05-clinical-safety-guardrails.md` |
| Module boundaries, jobs, caching | `docs/06-architecture.md` |
| Schema, constraints, RLS | `docs/08-data-model.md` |
| Endpoints, error envelope, rate limits | `docs/09-api-spec.md` |
| Who can see which field | `docs/10-rbac-access-matrix.md` |
| Plans, proration, renewals, RBI AFA rule | `docs/11-subscriptions-billing.md` |
| Attribution, commission ledger, payouts | `docs/12-partner-commission.md` |
| Consent, retention, breach clock | `docs/13-privacy-dpdp.md` |
| Golden vectors | `docs/16-test-strategy.md` |

## Ask before deciding

Adding/changing a rule-pack constant or medical override · widening what a coach or partner can see ·
price, entitlement, trial or refund behaviour · a new SDK touching health data or payments · schema
changes to `users`, `health_profiles`, `consents`, `subscriptions`, `commissions` · any copy shown to
a user about a medical condition.

## Definition of done

Governing doc cited in the PR · tests written · golden vectors re-run if the engine changed ·
error envelope respected · no PII in logs · no new lint/type warnings · `.env.example` updated ·
rule pack version bumped + changelog if constants changed · doc updated in the same PR if behaviour diverged.
