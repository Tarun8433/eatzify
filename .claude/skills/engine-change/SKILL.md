---
description: Change the diet engine or a rule-pack constant safely, with golden vectors re-run and the safety layer intact
disable-model-invocation: true
argument-hint: <what to change>
---

## Change requested

$ARGUMENTS

## Read first

`docs/04-diet-engine-spec.md`, then `docs/05-clinical-safety-guardrails.md`, then the active pack in
`config/rule-packs/`.

## Before writing code, tell me

1. Which pipeline step (`docs/04` §2) this touches.
2. Whether it changes a clinical constant. If yes, it needs a rule-pack version bump and a
   `reviewed_by` from someone with a nutrition qualification — flag it and propose the YAML diff
   rather than writing it.
3. Which golden vectors in `docs/16` §2 will change, with before/after numbers and the reason.
4. Whether any safety floor or gate in `docs/05` §2–§3 is affected. If the change weakens one, stop
   and tell me instead of implementing it.

## Then

- Implement in `packages/diet-engine`. Purity rules apply: no clock, no random, no I/O.
- Run `npm run test:golden`. Report every vector that moved.
- Add a new golden vector if this introduces behaviour none of the existing twelve covers.
- Update `docs/04` in the same change if the spec was wrong.

## Never

Edit a golden vector's expected output to make a change pass. Reorder or skip the safety clamp and
gate steps. Introduce a numeric literal outside the rule pack.
