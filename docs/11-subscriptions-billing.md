# 11 — Subscriptions, Pricing & Billing

## 1. Tier structure (revised — see ADR-008)

| Tier | Price | What it is |
|---|---|---|
| **FREE** | ₹0 | One template plan, basic calorie/protein view, 7-day history, ads-free. Acquisition. |
| **BASIC** | see matrix | Personalised engine plan, full logging, weekly progress, 2 regenerations/day |
| **PRO** | see matrix | + alternates, PDF export, unlimited history, advanced analytics, priority support, coach-ready |
| **Coaching** | partner-priced | Sold by the partner. Eatzify charges the partner a platform fee, not the client. |

Free tier restrictions worth stating explicitly: never restrict a **safety** feature. Floors,
warnings, referral screens and the disclaimer are free-tier. Restrict convenience, not protection.

## 2. Price matrix (from your spec, with duration discount enforced)

Prices are GST-inclusive, in ₹.

| Tier | 3 M | 6 M | 9 M | 12 M | Monthly equivalent (12M) |
|---|---|---|---|---|---|
| BASIC | 699 | 1,199 | 1,599 | 2,199 | ₹183 |
| PRO | 1,799 | 2,799 | 3,799 | 4,999 | ₹417 |

Chosen as the mid-point of your ranges. Two things to fix from the original matrix:
- **Your discount ladder doesn't hold.** BASIC 3M at ₹599 vs 12M at ₹1,799 is a 25 % benefit, but 3M
  at ₹799 vs 12M at ₹2,499 is only 22 %, and the ranges overlap enough that a customer comparing two
  quotes could see 12M as *worse* value per month. Pick one price per cell. The ladder must be
  monotonic: 3M base → 6M ≈ −12 % → 9M ≈ −18 % → 12M ≈ −25 % per month.
- **Badges:** "Most Popular" on 6M, "Best Value" on 12M — as you specified. Anchor with a visible
  crossed-out MRP on 6M/12M only, and never fabricate an MRP you never charged.

There is no monthly plan in this matrix. Add one (₹249 BASIC / ₹549 PRO) — it is your trial-conversion
landing spot and your churn-recovery offer. A first purchase of ₹699 minimum is a real barrier at this
ARPU. Doc 19 Q6.

## 3. Store fees and net revenue (doc 00 §5)

- Play service fee on auto-renewing subscriptions: **15 %**.
- India retains the current fee structure until **30 September 2027**; the June 2026 service/billing
  fee split applies only to US/UK/EEA buyers.
- India permits an **alternative billing system alongside Play billing**, reducing Play's fee by
  **4 pp** (15 % → 11 %), with enrolment, a compliant choice screen, and reporting obligations.

Net revenue per sale, PRO 12M at ₹4,999 (GST 18 % inclusive):

| Route | Gross | GST out | Store fee | Gateway | Net to you |
|---|---|---|---|---|---|
| Play billing | 4,999 | 762 | 750 (15 %) | — | **3,487** |
| Play + alt billing | 4,999 | 762 | 550 (11 %) | ~100 (2 %) | **3,587** |
| Web (Razorpay), app honours entitlement | 4,999 | 762 | — | ~100 (2 %) | **4,137** |

Web checkout is worth ~₹650 per 12M PRO sale versus Play. But read Play's payments and anti-steering
policy carefully before putting any purchase prompt in the app that points at your website. The safe
pattern: a web funnel that acquires and charges outside the app entirely, with the app simply
recognising an existing entitlement at login. Alternative billing becomes worth its engineering cost
somewhere around ₹15–20 lakh/year of in-app revenue.

## 4. Entitlement resolution

```
GET /auth/me → entitlements: {
  "plan.regenerate_per_day": 2,
  "plan.alternates": false,
  "export.pdf": false,
  "history.days": 90,
  "coach.chat": false,
  "support.priority": false
}
```
Resolved server-side from `tier_entitlements`, cached 5 min in Redis, invalidated on every
subscription event. **The client never computes an entitlement.** It renders what it's told and
handles `ENTITLEMENT_REQUIRED` (403) by showing the upgrade sheet.

## 5. Lifecycle state machine

```
                 ┌──────────┐
  purchase ─────▶│ trialing │──── trial ends, payment ok ──▶┌────────┐
                 └────┬─────┘                              │ active │◀── renewal ok ──┐
                      │ cancel                              └───┬────┘                 │
                      ▼                                         │ payment fails        │
                 ┌───────────┐                                  ▼                      │
                 │ cancelled │◀── cancel ────────────── ┌──────────┐  retry (3 days)   │
                 └───────────┘                          │ past_due │───────────────────┘
                      ▲                                 └────┬─────┘
                      │                                      │ retries exhausted
                      │                                      ▼
                      │                                 ┌───────┐  7 days
                      └───────────────────────────────  │ grace │──────▶ expired → FREE
                                                        └───────┘
```

`expired` retains all user data (subject to retention policy) and restores full access instantly on
repurchase. Never delete a user's history because they stopped paying — it's their data, and it's your
best win-back asset.

## 6. Trial

- 7 days, BASIC or PRO, one per identity keyed on `phone_hash` (not device — devices are shared, and
  device-keyed trials punish families).
- Payment method captured up front; converts unless cancelled.
- **Mandatory reminder 48 h before conversion** (email + push). This is not optional: silent
  conversion after a free trial is the top driver of chargebacks and Play policy complaints.
- Cancel-in-trial keeps access until the trial's end date. No clawback.
- Abuse: max 1 trial per phone hash lifetime; a second attempt shows the paid options directly.

## 7. Mid-term upgrade with proration

```
remaining_days     = ceil(ends_at - now)
total_days         = ends_at - starts_at
unused_paise       = floor(paid_paise × remaining_days / total_days)
credit_paise       = min(unused_paise, new_price_paise)          -- never a cash refund
amount_due_paise   = new_price_paise - credit_paise
```
Worked example: PRO 12M ₹4,999 bought 100 days ago (265 days remaining) → unused = ₹3,679. Upgrading
to a ₹5,999 tier costs ₹2,320. Show the arithmetic on screen; opaque proration generates tickets.

Rules: downgrades take effect at period end, never immediately (no refunds). Upgrades are immediate.
Store both the closing entry on the old subscription and the credit on the new one — never mutate the
old row. Commission on an upgrade accrues on `amount_due`, not on the new plan's full price (doc 12).

## 8. Renewals and the RBI constraint (doc 00 §6)

Under the **Digital Payments – E-mandate Framework, 2026**:
- Auto-debits ≤ ₹15,000 renew silently once the mandate is registered.
- Auto-debits **> ₹15,000 require AFA on every transaction**.
- The issuer must send a pre-debit notification ≥ 24 h before, and a post-debit confirmation.
- Users can pause a single debit or revoke the mandate at any time.

Consequences for your catalogue:

| Price point | `requires_afa` | Renewal UX |
|---|---|---|
| All BASIC and PRO cells (≤ ₹4,999) | false | Silent auto-renew. Send your own T-7/T-3 notices anyway. |
| Partner-sold coaching above ₹15,000 | **true** | **Assisted renewal**: notify at T-7, deep-link to an AFA checkout, do not attempt a silent debit. |

Design implication: `subscriptions.requires_afa` is computed at checkout from the price and drives a
different renewal job path. Any coaching product priced above ₹15,000 annually should be billed
monthly or quarterly instead — that is the cleaner fix. Doc 19 Q7.

Your own notification schedule (independent of the issuer's): T-7, T-3, T-0, then day 1 and day 3 of
`past_due`, then expiry. Notification copy must state the exact amount and the exact date.

## 9. Refunds

Your current Subscription screen promises a **"7-Day Money Back Guarantee — no questions asked"**. Be
careful: for Play-billed purchases, refunds run through Google, and Google's own refund window and
process govern the user's experience. You can honour a goodwill refund out-of-band, but you cannot
promise a mechanism you don't control.

Policy to actually ship:
- Web/Razorpay purchases: 7-day refund, self-serve, prorated to zero (full refund) if no plan has
  been generated; otherwise full refund at your discretion for the first 7 days.
- Play purchases: direct users to Play's process; process goodwill refunds manually where Play declines.
- Every refund reverses the associated commission entry (doc 12 §3).
- Never refund after 7 days on a discounted long-duration plan; state this plainly at purchase.

## 10. UI defects to fix (from the current build)

- Subscription screen shows **"Upgrade to Premium — Go Premium"** at the top *while* displaying an
  active Premium Yearly subscription below it. Mutually exclusive states rendering simultaneously
  (doc 15 D-12).
- Same screen shows **"Auto-renew: Disabled"** alongside a **"Cancel Subscription"** button. If
  auto-renew is off there is nothing to cancel — the action is "don't renew", already done. Show
  "Renew now" instead.
- "365 DAYS LEFT / STARTED 6 May 2026 / EXPIRES 6 May 2027" — a subscription started on the day it's
  viewed and showing exactly 365 days is demo data leaking into a production screen.
- "Restore Purchases" implies IAP; make sure it actually calls the Play billing restore path and
  handles the "no purchases found" empty state.
