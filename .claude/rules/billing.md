---
paths:
  - "api/src/modules/billing/**/*.ts"
  - "api/src/modules/partner/**/*.ts"
---

# Billing & commission rules

Governing specs: `docs/11-subscriptions-billing.md`, `docs/12-partner-commission.md`.

- Integer paise everywhere. Commission rates as `rate_bps` (basis points), never a float percentage.
- Commission is on **net** revenue (gross − GST − store fee), never gross.
- Ledger is append-only. Refunds and chargebacks post offsetting `reversal` entries — never update or
  delete an existing entry.
- Nightly invariant: `SUM(paid commission entries) == SUM(paid payouts)`. If it fails, page someone.
- Entitlements are resolved server-side. The client never computes one.
- `requires_afa` is derived from price vs `AFA_THRESHOLD_PAISE` (₹15,000, RBI E-mandate Framework
  2026). Above the threshold, do not attempt a silent debit — route to assisted renewal.
- Webhooks are signature-verified and idempotent by provider event id. Replays must be no-ops.
- Trial: one per `phone_hash` lifetime. Mandatory reminder 48 h before conversion.
- Proration credits never become cash refunds. Close the old subscription row, don't mutate it.
