# 13 — Privacy & DPDP Compliance

**Not legal advice.** This is an engineering specification derived from the DPDP Act 2023 and the DPDP
Rules 2025. Get it reviewed by a lawyer before launch.

## 1. Your position under the law

Eatzify is a **Data Fiduciary**. It processes:
- Personal data: name, phone, email, city, DOB.
- **Health-adjacent data**: weight, BMI, declared medical conditions, allergies, food logs, medication
  screening answers. This is the sensitive core of the product.
- And — critically — it **discloses that data to third parties (coaches, partners) for commercial
  purposes**. That disclosure is the highest-risk processing in the whole system.

Timeline (doc 00 §7): Rules notified 13 Nov 2025 · Consent Manager provisions from 13 Nov 2026 ·
**all other substantive obligations from 13 May 2027**. Build to the 2027 standard now; retrofitting
consent onto a live user base is far more expensive than designing it in.

## 2. The seven principles, mapped to build tasks

| Principle | What it means here | Build task |
|---|---|---|
| Consent & transparency | Itemised, standalone notice per purpose | Consent screens, `consents` table, notice versioning |
| Purpose limitation | Health data collected to build plans may not be used to target marketing | §5 targeting restrictions, purpose tags on every query path |
| Data minimisation | Don't collect "Allergies: dust, pollution". Don't collect what no rule consumes. | Field audit (§4) |
| Accuracy | Users can correct their data | Editable profile, 48 h log edit window |
| Storage limitation | Purpose-based retention, erase when purpose ends, **48 h notice before erasure** | Retention table (§6) + `retention.purge` job |
| Security safeguards | Encryption, access control, logging | §7 |
| Accountability | Records, audit trail, breach response | `audit_log`, breach playbook (§8) |

## 3. Consent design

**Four separate, independently revocable consents.** Not one checkbox.

1. **Account & service** (necessary) — identity, authentication, subscription management.
2. **Health processing** (required for plan generation) — height, weight, conditions, allergies, logs,
   used to generate and adjust your diet plan.
3. **Coach sharing** (optional, per coach, scoped, expiring) — see doc 10 §3.
4. **Marketing communications** (optional) — promotional push/SMS/email. Default **off**.

Rules:
- Notice is **standalone** — its own screen, not buried in T&C. Plain language, English + Hindi.
- Each notice has a `notice_version`; the version the user agreed to is stored with the consent row.
- Withdrawal is as easy as granting: one screen, "Privacy & data", each item with a toggle.
- Withdrawing (2) stops plan generation but does not delete history until retention expires or
  deletion is requested — explain that on the screen, before they toggle.
- Withdrawing (3) immediately cuts coach access, without deleting the coach's own notes.
- `consents` is append-only. Withdrawal is a new row, never an update.
- No dark patterns: no pre-ticked optional boxes, no "are you sure you want to lose your progress?"
  guilt copy, no burying the toggle three levels deep.

## 4. Field audit — collect less

| Field currently collected | Verdict |
|---|---|
| Allergies free-text ("Dust, pollution") | **Change to a closed food-allergen list.** Environmental allergies serve no rule in the engine and create sensitive-data liability for zero benefit. |
| Full phone + email visible in admin list views | **Mask by default**, reveal on audited action |
| Gender as free text | Replace with `sex_at_birth` (needed by the BMR equation) + optional gender identity, never required |
| "BMI Status: Obese" as a stored status | Derive at render time; don't store a judgemental label |
| Photos of meals | Store with the shortest useful retention (90 days) and never in a public bucket |
| Coach uploaded documents (qualifications) | Private bucket, signed URLs ≤ 5 min, never in the app DB |

## 5. Notification targeting — the one you need to change now

Your admin "Send Notification" screen offers **"Select Disease / Condition"** as a targeting filter
alongside goal and gender, with a "Generate with AI" button and an "URGENT" type used for
"Today new offer".

Sending a commercial offer to a segment defined by a medical condition is:
- a purpose-limitation problem (health data was collected to build plans, not to sell),
- a Play policy problem (sensitive-category ad targeting),
- and, practically, the kind of thing that produces a screenshot on social media that you cannot recover from.

**Rule to implement:** every notification carries `content_class ∈ {clinical, service, commercial}`.
- `condition` targeting is permitted **only** when `content_class = 'clinical'` (e.g. "your plan has
  been updated with lower-sodium options").
- `commercial` may target only tier, tenure, activity and geography.
- `URGENT` priority is reserved for `service` and `clinical`. A promotional offer is never urgent.
- Every send is logged with the segment definition, the operator, and the class. Reviewable.

## 6. Retention schedule

| Data | Retention | Trigger |
|---|---|---|
| Account (name, phone, email) | Until deletion + 30 days | Deletion request or 3 years inactive |
| Health profile & conditions | 3 years after last activity, then erase | Inactivity or withdrawal of consent (2) |
| Measurements & food logs | 3 years after last activity | Same |
| Diet plans & traces | 3 years (needed to explain a past plan) | Same |
| Meal photos | 90 days | Rolling |
| Chat with coach | 1 year after assignment ends | Assignment end |
| Consent records | 7 years (evidence of lawful basis) | — |
| Audit log | 3 years, immutable | — |
| Payments & invoices | 8 years (Companies Act / GST) | — |
| Support tickets | 2 years | Closure |
| Screening answers (doc 05 §4) | 1 year | Rolling |

Erasure mechanics: **notify the user 48 hours before erasure** (Rules requirement) with a chance to
retain by logging in. Erasure is a real delete of health rows plus tombstoning of the user record for
financial-record integrity — not a `deleted_at` flag on everything.

## 7. Security controls

- Column-level encryption (pgcrypto or app-level AES-GCM with a KMS-held key) on
  `health_profiles.conditions`, `health_profiles.screening`, and coach document references.
- TLS 1.3 only; HSTS; certificate pinning in the app for the API host.
- Secrets in environment variables injected at deploy, never in the repo. Rotate quarterly.
- 2FA mandatory for `admin` and `super_admin`. No shared accounts.
- Database not reachable from the public internet. Bastion or private network only.
- Backups encrypted at rest with a separate key; restore drill quarterly.
- **No production data in staging, ever** (doc 06 §7).
- Log redaction filter as middleware, plus a lint rule against logging known PII field names. Test it.
- Rate limits and account lockout on OTP; no user enumeration in responses.

## 8. Breach response (72-hour clock)

Rules require intimation to affected individuals and a detailed report to the Data Protection Board
within 72 hours. Have this written down *before* you need it:

1. **T+0** Detect → declare an incident → assign an incident lead (named person, not a role).
2. **T+1h** Contain: revoke tokens, rotate keys, block the vector.
3. **T+6h** Scope: which tables, which users, which fields, from the audit log.
4. **T+24h** Draft user notification in plain language: what happened, what data, what they should do,
   who to contact.
5. **T+48h** Send user notifications.
6. **T+72h** File the report with the Board.
7. **T+7d** Post-mortem, control changes, ADR entry.

Keep a pre-drafted notification template in the repo. Drafting it under pressure produces the wrong
tone and the wrong facts.

## 9. Data subject rights — build these as features, not tickets

| Right | Implementation |
|---|---|
| Access | `POST /privacy/export` → async JSON + PDF bundle, download link expiring in 24 h |
| Correction | Editable profile; measurement correction with audit |
| Erasure | `POST /privacy/delete` → 7-day cooling-off, then execute per §6, email confirmation |
| Grievance | In-app grievance form → named Grievance Officer, published contact, 30-day SLA |
| Consent withdrawal | "Privacy & data" screen (§3) |
| Nominate | Nominee field to exercise rights on death/incapacity (a DPDP-specific right people forget) |

Publish: Privacy Policy, Terms, a Grievance Officer name and contact, and a data-retention summary.
Your current app links Terms and Privacy Policy from the subscription screen — make sure those pages
actually exist, match this document, and are versioned.

## 10. Children

No under-18s (doc 05 §3). Implementation: DOB gate with a `CHECK` constraint at the database level
(doc 08 §1), so a bug in the app cannot create a minor's record. If a minor is discovered post-hoc:
suspend the account, delete health data, notify, and log the incident. Do not build a
parental-consent flow unless you decide to serve minors deliberately — verifiable parental consent is
a significant compliance surface of its own.
