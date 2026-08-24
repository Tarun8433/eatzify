---
paths:
  - "test/**/*.dart"
---

# Testing rules

- Names: "should <expected> when <condition>".
- Every screen gets a widget test covering all four `ViewState` cases. This is the floor, not the goal.
- Controller tests mock use cases, not repositories or data sources.
- Golden tests for the shell and any screen with a complex layout; run them at 1.0 and 2.0 text scale.
- No real phone numbers, emails or names in fixtures.
- Integration tests cover the eight journeys in `docs/16-test-strategy.md` §3.
- Test the offline path for anything that writes: queue, reconnect, sync exactly once.
