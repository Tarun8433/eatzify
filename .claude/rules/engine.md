---
paths:
  - "api/packages/diet-engine/**/*.ts"
  - "api/config/rule-packs/**/*.yaml"
  - "api/src/modules/engine/**/*.ts"
---

# Diet engine rules

Governing spec: `docs/04-diet-engine-spec.md`. Safety layer: `docs/05-clinical-safety-guardrails.md`
(it can veto anything in 04).

## Purity

- No `Date.now()`, `new Date()`, `Math.random()`, `process.env`, DB, HTTP, or file I/O.
- Randomness comes from the seeded PRNG only: `seed = hash(user_id + plan_date + packVersion)`.
- Same input + same rule pack version must produce byte-identical output. Forever.

## Constants

- Every number comes from the rule pack. If you need a value that isn't there, add it to the YAML with
  an `authority` field (ICMR-NIN, sports-nutrition literature, or product decision) and reference it.
- Rule pack changes need a version bump, a changelog entry, and a `reviewed_by`. The pack directory is
  in the deny list — propose the diff, don't write it.

## Pipeline order is fixed

validate → BMR → TDEE → goal adjust → **safety clamps** → **condition gates** → protein → fat/fibre/
sodium/sugar → carbs remainder → medical overrides → candidate pool → meal distribution → fill →
alternates → round → validate totals → trace.

Steps 5 and 6 cannot be reordered, skipped, or made conditional. If a gate blocks, emit no plan at
all — a partial plan is worse than none.

## Protein

On **adjusted body weight**, never actual weight for users above IBW:
`IBW = 23.0 × (H/100)²` (Indian BMI reference) · `ABW = IBW + 0.25 × (W − IBW)`.
Floor `0.83 × W` (ICMR RDA). Cap `2.2 × ABW` and ≤40 % of kcal.

## Output

Every plan carries `rule_pack_version`, the input snapshot, and an ordered trace with one entry per
pipeline step. Round once, at the boundary. Then assert totals within tolerance — a failed assertion
is a bug, not a warning.

## Tests

Any change re-runs all golden vectors in `docs/16-test-strategy.md` §2. If a vector's expected output
changes, show the before/after and the reason **before** editing the test file. Never edit a golden
vector to make a change pass.
