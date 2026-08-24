# Project state

**Purpose: answer "where are we?" without reading the repo.** Overwrite this file when state
changes — it is a snapshot, not a history. History lives in `DECISIONS.md`.

Last verified: 2026-08-24 · verified by running the commands in the Checks table, not by reading code.

## Shape

```
health_pro/              monorepo · no git yet (see Blockers)
├── CLAUDE.md            Flutter scope + layout table
├── .claude/             1 settings.json · 9 rules · 7 skills · 2 agents
├── docs/                21 numbered specs + this file + DECISIONS.md + PLACEMENT.md
├── lib/ test/           Flutter — still the counter demo
└── api/                 backend
    ├── config/rule-packs/v1.0.0.yaml
    ├── packages/diet-engine/     the engine
    └── src/modules/engine/       loader + zod schema + EngineService
```

## Status

| Area | State | Evidence |
|---|---|---|
| Claude config | **done** | 9 path-scoped rules, globs verified against the real tree |
| Docs | **done** | 21 specs, doc 20 added this session |
| Rule pack v1.0.0 | **built, unapproved** | validates at boot; needs clinical sign-off (D-18) |
| Diet engine targets pipeline (doc 04 steps 1–10, 12) | **done** | 87 tests, 99.7 % stmt / 96.0 % branch |
| Engine steps 11, 13, 14 (pool, fill, alternates) | **blocked** | needs food DB (D-10) |
| Rule-pack loader + `EngineService` | **done** | 15 tests |
| Flutter deps | **done** | 144 packages resolve; `flutter analyze` clean bar the demo file |
| Flutter app code | **not started** | `lib/main.dart` is the counter demo |
| Backend `src/` beyond engine | **not started** | boilerplate fork first (D-11) |
| Admin panel | **not started** | AdminJS per doc 20 §3 — contradicts ADR-006 |
| git | **absent** | `.gitignore` files are inert |

## Checks — run these instead of trusting this table

| Command | Expect |
|---|---|
| `cd api && npm run test:engine` | 87 passed |
| `cd api && npx jest` | 15 passed |
| `cd api && npx ts-node scripts/validate-rule-packs.ts` | `ok v1.0.0` |
| `cd api/packages/diet-engine && npx jest --coverage` | ≥95 % stmt/func, ≥90 % branch |
| `flutter analyze` | 6 infos, all in `lib/main.dart` |
| `flutter test` | 1 passed |

## Open decisions blocking others

1. **GV-03 fat: 22 % or 25 %?** (D-12) — blocks trusting the muscle-gain path.
2. **GV-04 protein taper** (D-13) — needs a clinician. Blocks the older-diabetic path.
3. **GV-06 needs new inputs** (D-14) — the vector is arithmetically unsound.
4. **Clinical sign-off on the rule pack** (D-18) — blocks launch, not development.
5. **`tinymce` XSS** (D-17) — blocks shipping an admin panel.
6. **ADR-006 is stale** — doc 20 §3 says revise it; `docs/07-adr-log.md` still says Flutter web.
7. **No git.** Nothing is recoverable and no `.gitignore` applies.

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

1. `git init` — cheapest, highest-value, still missing.
2. Resolve D-12/D-13/D-14 so the golden vectors are trustworthy. D-13 needs a clinician.
3. Run `api/scripts/bootstrap-from-boilerplate.sh` — fork + prune. Needs network and `npm install`.
4. AdminJS on `foods` / `recipes` / `household_measures` (~1 day, doc 20 §3).
5. Start the household-measures table by hand, in parallel with everything.
6. E1 onboarding (backend) and the doc 14 §2 shell (Flutter) run alongside.

## Epic status (doc 17)

| Epic | Est | State |
|---|---|---|
| E1 identity & onboarding | 8–10 d | not started |
| **E2 food database** | 10–14 d | **not started — critical path** |
| E3 engine & plans | 8–10 d | ~60 % (engine done; persistence, revisions, alternates, override pending) |
| E4 logging & progress | 8–10 d | not started |
| E5 billing | 10–12 d | not started |
| E6 coach surface | 10–12 d | not started |
| E7 partner | 8–10 d | not started |
| E8 admin | 10–12 d | not started |
| E9 compliance | 6–8 d | not started |
| E10 hardening | 6–8 d | not started |
