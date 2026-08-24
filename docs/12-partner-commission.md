# 12 — Partner & Commission System

## 1. The margin problem — read this before setting rates

Your spec proposes 20–40 % commission, including recurring commission on renewals. Run the numbers on
the plan you were most excited about (coaching, 12M, ₹22,999, 40 %):

```
Gross collected                        ₹22,999
Less GST @18% (price is inclusive)     − ₹3,508   → net revenue ₹19,491
Less Play service fee @15% of gross    − ₹3,450
Less partner commission @40% of net    − ₹7,796
─────────────────────────────────────────────────
Left for delivery + platform + profit    ₹8,245   → ₹687 per month
```

₹687/month has to cover a human coach's time for that client, your infrastructure, support, payment
failures, and profit. It does not close. A coach handling 40 clients at ₹687 earns ₹27,480/month
gross for full-time work — below what an independent coach already charges directly.

This is why doc 01 and ADR-008 say: **don't sell coaching first-party.** Let the partner set and keep
the coaching fee, and charge them a platform fee. Then the numbers invert in your favour and their
incentive aligns with retention rather than with churning through signups.

Run the same math on the tiers you *should* sell:

| Product | Gross | Net rev | Play 15 % | Commission | Left |
|---|---|---|---|---|---|
| BASIC 12M ₹2,199 (25 %) | 2,199 | 1,864 | 330 | 466 | **1,068** |
| PRO 12M ₹4,999 (30 %) | 4,999 | 4,236 | 750 | 1,271 | **2,215** |
| PRO 12M ₹4,999 (30 %), web-billed | 4,999 | 4,236 | 0 (₹100 gateway) | 1,271 | **2,865** |

Those work. Note how much of your margin is decided by billing route, not by product.

## 2. Recommended commission structure

| Product | First purchase | Renewal | Upsell/upgrade |
|---|---|---|---|
| BASIC | 25 % of net | 10 % of net, 12 months max | 25 % of the incremental amount |
| PRO | 30 % of net | 12 % of net, 12 months max | 30 % of incremental |
| Coaching (partner-priced) | n/a — partner keeps the fee | n/a | n/a |
| Platform fee on coaching seats | you charge the partner ₹99–199/active client/month | | |

Rules that matter more than the rates:
- **Commission is on net revenue** (gross − GST − store fee), never on gross. Write this into the
  partner agreement in the same words the code uses.
- **Renewal commission is capped at 12 months.** Perpetual recurring commission on a low-ARPU
  subscription makes your unit economics permanently negative on the best cohorts.
- **Rates live in `partners.commission_tier` → a rate table**, never hardcoded, and are versioned so a
  historical entry can always be recomputed.
- Basis points (`rate_bps INT`), never percentages as floats.

## 3. Attribution

```
Signup with code/link → INSERT attributions (user_id, partner_id, code_used, channel)
                        → immutable. REVOKE UPDATE on the table.
```

| Question | Rule |
|---|---|
| Model | First-touch, locked at signup |
| Window | Code entered at signup, or deep-link click within 30 days pre-signup (stored client-side, sent once) |
| Multiple codes | First one wins. No re-attribution ever, including on re-install. |
| Self-referral | Blocked: partner's own `phone_hash`, and any account sharing the partner's device fingerprint within 24 h of the partner's own session, is flagged for review |
| Coach change | Changing coach does **not** change attribution. Commission follows the referrer; coaching follows the assignment. Keep these separate or you will get disputes. |
| Refund | Commission entry reversed (offsetting entry, never a delete) |
| Chargeback | Reversed + partner flagged if rate > 5 % of their volume |

## 4. Commission ledger mechanics

Append-only. Never update an amount; post an offsetting entry.

```
payment captured        → INSERT commission_entries(status='accrued', hold_until = now + 7 days)
hold window passes      → INSERT status transition to 'held' → 'payable' (job commission.settle)
payout run              → 'payable' rows attached to a payout, status 'paid'
refund/chargeback       → INSERT kind='reversal', negative amount, status matching the original
```

Reconciliation invariant, asserted nightly:
```
SUM(commission_entries.amount_paise WHERE status='paid')
  == SUM(payouts.gross_paise WHERE status='paid')
```
If it ever fails, page someone. A commission ledger that silently drifts destroys partner trust
permanently, and partners are your distribution.

## 5. Payouts, tax and KYC

- Cycle: monthly, on the 1st, for the previous calendar month's `payable` balance.
- Minimum: ₹1,000 (as you specified). Below threshold rolls forward.
- KYC before first payout: PAN (store **last 4 only** in the app DB; full PAN goes to your accounting
  system, not here), bank account, GSTIN if registered. Payout blocked until `kyc_status = verified`.
- **TDS on commission** to resident partners falls under section 194H. The rate was revised in the
  FY 2024-25 Budget — **confirm the current rate and threshold with your CA before you write the
  calculation**, and put the rate in a config table with an effective-from date so historical payouts
  stay reproducible. ⚠
- **GST:** if the partner is GST-registered, they invoice you for the commission and you take input
  credit; if not, check whether reverse charge applies to your arrangement. Again: CA, not code
  comments. ⚠
- Every payout generates a downloadable statement listing each commission entry, the TDS deducted, and
  the UTR. Partners will ask; automate it on day one.
- Payout execution: **manual approval, always.** No automated bank transfer without a human clicking
  approve, and no payout API credentials on the app server.

## 6. Partner levels and what they unlock

| Level | Name | Requirements | Unlocks |
|---|---|---|---|
| 1 | Affiliate | Signup + agreement | Referral code, earnings dashboard, masked referral list |
| 2 | Verified | ID + qualification document on file + agreement | Public profile, "Verified Partner" badge, client `basic`+`progress` scopes on grant |
| 3 | Coaching | Level 2 + active coaching agreement + client grant | `plan_edit`, `chat`, `health_conditions` on grant |
| — | Org (gym) | GST + agreement | Sub-partner management, roll-up earnings, single payout |

**Naming:** call it "Eatzify Verified Partner", not "Eatzify Certified Coach". You are not an
accrediting body (doc 00 §8), and the National Commission for Allied and Healthcare Professions Act
framework makes loose certification claims a bad place to be. Publish exactly what verification
means: *"We have checked this partner's identity and have a copy of the qualification they submitted.
Eatzify does not certify or accredit practitioners."*

## 7. Anti-fraud

| Vector | Control |
|---|---|
| Self-referral rings | Phone hash, device fingerprint, payment instrument reuse, velocity checks |
| Fake signups for joining commission | Commission accrues on **paid conversion only**, never on signup |
| Refund farming | 7-day hold before payable; reversal on refund; partner-level refund-rate monitoring |
| Trial abuse | 1 trial per phone hash lifetime |
| Code stuffing (spraying codes at organic users) | Attribution requires the code at signup or a tracked click; no post-hoc attachment |
| Payout account swapping | Bank change freezes payouts for 7 days + re-verification |

## 8. What partners see (and don't)

Per doc 10. Summary: aggregate earnings, their own referral list with masked identity at level 1,
client progress only with a grant, **no export of client PII at any level, ever**. Your spec's
"Partner ko sirf apne users ka data dikhe" is right and is enforced at both the query layer and RLS.

## 9. Partner dashboard metrics that actually drive behaviour

Show: active clients, clients at risk (no log ≥3 days), renewals due in 30 days, commission payable,
next payout date. Do **not** lead with lifetime earnings — it's a vanity number that doesn't tell them
what to do today. The at-risk list is the single most valuable widget you can give a coach, and it
costs you nothing.
