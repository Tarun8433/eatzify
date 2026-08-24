# 10 — Roles & Field-Level Access Matrix

This document answers the question your spec raises and doesn't resolve: *how much of a client's data
does a partner get to see?* The short answer: **less than your spec assumes, and only with a consent
grant that the client can revoke.**

## 1. Roles

| Role | Who | Basis for access |
|---|---|---|
| `client` | end user | own data |
| `coach_l1` (Affiliate Partner) | referrer, no coaching relationship | commercial contract only |
| `coach_l2` (Verified Partner) | verified coach, guidance only | consent grant, scope `basic,progress,plan_view` |
| `coach_l3` (Coaching Partner) | active coaching relationship | consent grant, scope `+plan_edit,chat,health_conditions` |
| `partner_org` (Gym owner) | onboards coaches | aggregate only, never client-level |
| `support` | your support staff | ticket-scoped, time-boxed, audited |
| `admin` | ops | audited, purpose-recorded |
| `super_admin` | you | everything, audited, 2FA mandatory |

**Key principle: the level does not grant access. The consent grant does.** The level caps what a
grant *may* contain. A coach_l3 without a grant sees nothing.

## 2. Field matrix

Legend: ✅ full · 🔒 masked · 📊 aggregate only · ❌ none · 🔍 audited read

| Field | client | coach_l1 | coach_l2 | coach_l3 | partner_org | support | admin |
|---|---|---|---|---|---|---|---|
| Display name | ✅ | 🔒 first name + initial | ✅ | ✅ | 📊 count | ✅ | ✅🔍 |
| Phone | ✅ | ❌ | 🔒 last 4 | ✅ | ❌ | 🔒 last 4 | ✅🔍 |
| Email | ✅ | ❌ | ❌ | ✅ | ❌ | 🔒 domain | ✅🔍 |
| City | ✅ | 🔒 state | ✅ | ✅ | 📊 | ✅ | ✅ |
| Age | ✅ | 📊 band | ✅ | ✅ | 📊 band | ✅ | ✅ |
| Sex at birth | ✅ | ❌ | ✅ | ✅ | 📊 | ❌ | ✅🔍 |
| Height | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅🔍 |
| Weight (current) | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅🔍 |
| Weight history | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅🔍 |
| BMI | ✅ | ❌ | ✅ | ✅ | 📊 | ❌ | ✅🔍 |
| **Medical conditions** | ✅ | ❌ | ❌ | ✅🔍 | ❌ | ❌ | ✅🔍 |
| **Screening answers (doc 05 §4)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | 🔍 super_admin only |
| Allergies | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅🔍 |
| Goal | ✅ | 📊 | ✅ | ✅ | 📊 | ✅ | ✅ |
| Diet plan | ✅ | ❌ | view | view + edit | ❌ | ❌ | ✅🔍 |
| Food logs | ✅ | ❌ | 📊 adherence % | ✅ | ❌ | ❌ | ✅🔍 |
| Chat with coach | ✅ | ❌ | ❌ | ✅ | ❌ | 🔍 on ticket | 🔍 on ticket |
| Plan tier | ✅ | ✅ | ✅ | ✅ | 📊 | ✅ | ✅ |
| Payment amounts | ✅ | 📊 own commission | 📊 | 📊 | 📊 | 🔒 last 4 of card | ✅🔍 |
| Support tickets | ✅ own | ❌ | ❌ | ✅ own clients | ❌ | ✅ | ✅ |

Reading the row that matters most: **coach_l2 does not see medical conditions.** Your spec's Level 2
("Verified Coach: all above + diet view + limited guidance") would give conditions to anyone verified.
A verified coach with no coaching relationship has no need for a diabetes diagnosis, and giving it to
them is processing without a purpose.

## 3. Consent grant scopes

```
basic              display name, age band, goal, plan tier
progress           weight series, adherence %, steps, streaks
plan_view          diet plan read-only
plan_edit          diet plan override
chat               in-app messaging
health_conditions  declared conditions and allergies
```

Grant rules:
- Created only when the **client** accepts a coach invite, or explicitly adds a coach from settings.
- Default expiry = subscription end date, or 180 days, whichever is sooner.
- Client can revoke any scope, any time, from a single "Who can see my data" screen — one tap, no
  retention dark pattern, effective immediately (cache TTL ≤ 60 s for grants).
- Revocation or expiry moves the assignment to `paused` and the coach's UI shows a neutral
  "access ended" state, not the last-cached data.
- Every grant change writes to `consents` (append-only) and `audit_log`.
- A coach may request a scope; only the client can grant it.

## 4. Admin & support constraints

- Support access is **ticket-scoped**: opening a ticket grants read on the fields needed for that
  ticket class, for 72 hours, and every read is audited. No standing access to health data.
- Admin reads of any health field require a `reason` header value from a closed list
  (`support_ticket`, `fraud_review`, `data_subject_request`, `safety_review`) which lands in the audit
  log. Un-reasoned reads are rejected.
- `super_admin` requires TOTP 2FA. No shared accounts. No "admin@" login.
- Bulk export of PII: super_admin only, reason required, generates a watermarked file, logged, and the
  export itself expires in 24 hours.

## 5. Hard prohibitions

1. **No coach or partner may export client PII.** No CSV, no PDF containing contact details, no
   "share client list". This is the difference between a platform and a lead-generation leak.
2. **No partner sees another partner's clients.** Enforced at query level and RLS level.
3. **No partner sees a client's conditions unless they are a coach_l3 with an active grant.**
4. **No role can override a safety floor** (doc 05 §2). The API rejects it regardless of role.
5. **No role can see the eating-disorder screening answer** except super_admin under a
   `safety_review` reason. It exists to protect the user, not to inform commerce.
6. **Partner dashboards show aggregates, not identifiable progress**, at level 1.

## 6. Implementation notes

- One `@RequiresScope('progress')` decorator on the controller + a `ConsentGuard` that resolves the
  grant, plus RLS as the backstop. Two independent layers.
- Field masking happens in a **serialiser keyed by (viewer role, grant scopes)** — never by
  conditionals scattered through controllers. One place to audit, one place to test.
- Write a test per row of the matrix above. That test file is your compliance evidence.
- The current admin UI has two separate "All Users" screens, one of which lists full emails and phone
  numbers with an unrestricted CSV export. Both need to be consolidated into one screen built on this
  matrix (doc 15 D-06, D-07).
