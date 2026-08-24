---
paths:
  - "api/**/*.spec.ts"
  - "api/**/*.e2e-spec.ts"
---

# Testing rules

- Names: "should <expected> when <condition>".
- Coverage floors: engine 95 %, billing 90 %, everything else 60 %.
- Mock external services, never internal modules. Repositories get a real Postgres via Testcontainers.
- Never edit a golden vector to make code pass. Golden vectors are the specification.
- Every row of the `docs/10` access matrix has a test. That file is compliance evidence, not optional.
- No real phone numbers, emails or names in fixtures. Use the synthetic generator.
- Every constraint added to the schema gets a test proving the rejection path.
- Clean up side effects in `afterEach`. No test may depend on another test's ordering.
