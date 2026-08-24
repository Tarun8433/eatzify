# Claude Code Task Templates

Paste-and-fill prompts. Each one names its governing doc, because an unanchored prompt produces
plausible code that quietly contradicts a decision you already made.

---

## T1 — Implement an API endpoint

```
Implement <METHOD> <PATH> per docs/09-api-spec.md §<N>.

Constraints:
- Error envelope exactly as specified in §2. user_message comes from the server-side copy table
  (docs/05-clinical-safety-guardrails.md §7) — do not invent user-facing strings.
- DTO validation with class-validator; reject unknown properties.
- Scope the query by the authenticated caller. Never trust a user_id from the request body.
- If this endpoint returns a health field, add the audit interceptor and a docs/10 matrix test.
- Idempotency-Key handling if this creates money or a plan.

Deliver: controller, service, DTOs, repository method, contract test, and a docs/09 diff if the spec
needs correcting.
```

## T2 — Change the diet engine

```
Change the diet engine: <describe>.

Read first: docs/04-diet-engine-spec.md and docs/05-clinical-safety-guardrails.md.

Constraints:
- The engine stays pure: no I/O, no clock, no random (seeded PRNG only).
- No numeric literal in src/. Add the constant to config/rule-packs/<version>.yaml.
- Bump the rule pack version and add a changelog entry with a reviewed_by placeholder.
- Re-run all golden vectors in docs/16-test-strategy.md §2. If a vector's expected output changes,
  show me the before/after and the reason BEFORE editing the test.
- Safety clamps in §4 cannot be reordered, weakened or bypassed.

Deliver: engine diff, rule pack diff, updated/added golden vectors, and a note on which vectors moved.
```

## T3 — Add a screen

```
Build the <NAME> screen per docs/14-flutter-app-spec.md.

Constraints:
- Clean Architecture: entity → repository interface → use case → model → data source → repo impl →
  controller → binding → page → widgets. List the files before writing them.
- GetX: Get.lazyPut in the binding; controller has no Flutter imports.
- Use the sealed ViewState<T> pattern (§3): Loading, Empty, Failed, Ready. All four rendered.
- Theme tokens only: no hardcoded colors, sizes, radii or strings. l10n keys for every string (en+hi).
- Touch targets ≥48dp. Test at 200% font scale.
- Enum values are mapped through l10n before display — never show `lose_weight` to a user.

Deliver: files, plus a widget test covering all four states.
```

## T4 — Schema change

```
Add/change <TABLE/COLUMN> per docs/08-data-model.md §<N>.

Constraints:
- Forward-only migration, expand/contract compatible with the previous release.
- Constraints in the DB, not only in the app (CHECK, UNIQUE, FK). Name them.
- If this table holds health data: add it to the docs/13 retention table, enable RLS, and add the
  encryption note.
- Money is BIGINT paise. Timestamps are TIMESTAMPTZ.
- Update docs/08 in the same change.

Deliver: migration up/down, entity, repository update, doc diff, and a Testcontainers test proving the
constraint rejects bad input.
```

## T5 — Review my code

```
Review <PATH> against:
- docs/06-architecture.md (module boundaries)
- CLAUDE.md §2 (hard rules)
- docs/05 (if it touches targets, copy, or health data)

Report in this order: (1) hard-rule violations, (2) safety/privacy issues, (3) architecture drift,
(4) bugs, (5) style. Be specific, cite line numbers, and show the fix. Don't rewrite the file
wholesale — tell me what's wrong first.
```

## T6 — Fix an audit defect

```
Fix defect <D-NN> from docs/15-ux-audit-screenshots.md.

Constraints:
- Fix the cause, not the symptom. If the root cause sits in another layer, say so and fix it there.
- If it's a safety or data-integrity defect, add the test that would have caught it.
- If the defect exists in more than one place (there are duplicate implementations in this codebase),
  find all of them.

Deliver: fix, test, and a list of any other places the same bug exists.
```

## T7 — Session bootstrap (use at the start of a fresh context)

```
Read CLAUDE.md, then docs/00-research-findings.md §10 (risk register), then <the governing doc for
today's task>. Summarise back to me in 10 lines: what this system is, the three hard rules most
relevant to today's task, and anything in the docs that conflicts with what I've asked for. Then wait.
```

---

## What not to ask for

- "Build the whole diet app." Any model, including me, will produce something plausible and wrong at
  this scope. Work an epic at a time from doc 17.
- "Make the engine smarter with AI." See ADR-001.
- "Skip the tests for now." The golden vectors are the only thing standing between a rule-pack edit
  and a user eating 900 kcal a day.
- "Just make the coach able to see everything." Doc 10 exists because that request is the one most
  likely to end the company.
