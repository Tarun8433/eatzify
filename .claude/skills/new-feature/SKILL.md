---
description: Plan a full Flutter feature slice before implementing it, mapped to the PRD and API spec
disable-model-invocation: true
argument-hint: <feature name>
---

## Feature requested

$ARGUMENTS

## Produce a plan first — no code in your first response

1. **Requirements.** Which FR numbers in `docs/02-prd.md` does this satisfy? Quote them. Which
   acceptance criteria will prove it works?
2. **API surface.** Which endpoints from `docs/09-api-spec.md`? List anything the backend does not yet
   expose — that's a blocker, not something to stub.
3. **Domain.** Entities, repository contracts, use cases. Name each one.
4. **Screens.** Which screens, under which tab, in which order. Reuse before adding.
5. **State.** Controllers and what each owns. Where offline caching applies (`docs/14` §4).
6. **Entitlements.** Which tier gates what, and what the paywall path looks like. Remember: safety
   features are never gated.
7. **Risks.** Anything in `docs/05` (safety/tone) or `docs/13` (privacy) this touches.
8. **Slices.** Break it into PR-sized pieces, each independently shippable and testable.

Then stop and wait for me to pick a slice.
