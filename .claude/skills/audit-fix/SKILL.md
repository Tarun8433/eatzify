---
description: Fix a numbered defect from the Eatzify UX/QA audit, including all duplicate occurrences
disable-model-invocation: true
argument-hint: <defect id, e.g. D-14>
---

## Defect

Fix `$ARGUMENTS` from `docs/15-ux-audit-screenshots.md`.

## Steps

1. Quote the defect and its severity. If it's P0, say what it currently does to a real user.
2. Find the **root cause**, not the symptom. If the cause sits in another layer — or on the backend —
   say so and fix it there, or tell me it's a backend ticket.
3. **Search for duplicates.** This codebase has duplicate implementations (two admin user screens,
   four navigation shells). Grep for the pattern; the same bug usually exists more than once. List
   every occurrence before fixing any.
4. Fix all occurrences.
5. Add the test that would have caught it. For data-integrity and safety defects this is mandatory,
   not optional.
6. If the defect exists because two screens implement the same thing, consolidate them rather than
   fixing both.

## Output

Root-cause explanation in two sentences, the list of occurrences found, the fix, the test, and any
follow-up tickets the fix revealed.
