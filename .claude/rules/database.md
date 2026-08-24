---
paths:
  - "api/src/migrations/**/*.ts"
  - "api/src/**/*.entity.ts"
---

# Database rules

Governing spec: `docs/08-data-model.md`.

- Forward-only migrations. Expand/contract: add nullable → backfill → switch reads → drop in a later
  release. Never add-and-drop in one migration.
- Constraints in the database, not only in the app: `CHECK`, `UNIQUE`, `FOREIGN KEY`. Name them.
  The Atwater consistency check on `foods` and the adult-only check on `profiles` are load-bearing.
- `BIGINT` paise for money. `TIMESTAMPTZ` for time. `NUMERIC` for macros, never `FLOAT`.
- Append-only tables (`consents`, `commission_entries`, `audit_log`) must have `UPDATE`/`DELETE`
  revoked from the app role. Corrections are new offsetting rows.
- Any table holding health data: add it to the retention table in `docs/13` §6, enable RLS, and note
  the encryption requirement.
- `is_demo BOOLEAN` on every table with user-visible content. Metrics exclude it.
- Every constraint needs a Testcontainers test proving it rejects bad input.
