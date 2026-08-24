---
description: Add or change a database table or column with constraints, migration, RLS and retention wiring
disable-model-invocation: true
argument-hint: <table.column or description>
---

## Change requested

$ARGUMENTS

## Steps

1. Find the table in `docs/08-data-model.md` and quote the current definition. If it isn't there, say
   so and propose where it belongs.
2. State whether this column holds health data, PII, or money. That decides everything below.
3. Write the migration: forward-only, expand/contract compatible with the currently deployed release.
   Say explicitly which later release does the contract step.
4. Add named DB-level constraints. `CHECK` for ranges and enums, `UNIQUE` where a duplicate is a bug,
   `FOREIGN KEY` always.
5. If health data: add to the `docs/13` §6 retention table, enable RLS with the grant-scoped policy,
   note the encryption requirement.
6. If money: `BIGINT` paise. If time: `TIMESTAMPTZ`. If macros: `NUMERIC`.
7. Add `is_demo` if the table holds user-visible content.
8. Write a Testcontainers test proving each new constraint rejects bad input.
9. Update `docs/08` in the same change.

## Output

Migration, entity, repository update, test, doc diff, and a one-line rollback plan.
