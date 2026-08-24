---
description: Audit a change for clinical-safety and privacy violations before merge
argument-hint: <branch, path, or nothing for staged>
---

## Diff under review

!`git diff $ARGUMENTS`

## Audit

Check the changes above against `docs/05-clinical-safety-guardrails.md` and
`docs/13-privacy-dpdp.md`. Use `checklist.md` in this skill directory for the full list.

Report findings in this order, each with a severity and a concrete fix:

1. **Safety floor or gate weakened** — any change that lets a target fall below the `docs/05` §2
   floors, any gate made conditional, any auto-reduction path missing the 3-strike freeze.
2. **PII or health data leaking** — into logs, exceptions, analytics events, URL params, or a response
   a role isn't entitled to see.
3. **Consent bypassed** — a health field read without a grant check, a grant read without an expiry
   check, an audit row not written.
4. **Copy risk** — any user-facing string about a medical condition not verbatim from §7, any claim to
   treat/cure/manage/reverse a condition, any shame or urgency framing.
5. **Money integrity** — float arithmetic, mutated ledger rows, missing idempotency.

If a category is clean, say so explicitly rather than omitting it.
