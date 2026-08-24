# Rule packs

Versioned YAML holding **every** nutrition constant — calorie targets, macro splits, activity
multipliers, thresholds. Hard rule 1: no nutrition constant may appear in `src/`. Grep for a literal
like `1.55` or `0.8` there; the correct answer is zero hits.

Authoritative spec: `../../../docs/04-diet-engine-spec.md`. Safety bounds that a pack may never
violate: `../../../docs/05-clinical-safety-guardrails.md`. Golden vectors that must pass after any
change: `../../../docs/16-test-strategy.md`.

**This directory is `Edit`-denied in `.claude/settings.json`.** Claude can read it and propose a diff;
applying one is a human decision with a reviewer, not an agent's mid-session edit. Every change bumps
`RULE_PACK_VERSION` and re-runs the golden vectors. No exceptions.

Loaded at boot via `js-yaml`, schema-validated with `zod`, path from `RULE_PACK_DIR` (`.env.example`).
