# Payments — phase plan and status

Where the payment gateway (Cashfree) and in-app purchases (Google Play, App Store) stand, phase by
phase, with what is done and what is left.

**As of 30 Sep 2026.** This file was empty when this status was written, so the phases below are
rebuilt from the code, `docs/DECISIONS.md` and the tests. Phase 3 and Phase 4 are the code's own
numbering (`api/src/**` says "payments plan, Phase 3/4" in a dozen places); Phases 1–2 are
reconstructed from what those phases assume already exists, and Phases 5–6 are what is left over.
Percentages are a judgement, not a measurement.

| # | Phase | Status | Done | Evidence |
|---|---|---|---|---|
| 1 | Cashfree checkout on stub rails | **done** | 100 % | `checkout.service.ts`, `POST /billing/checkout`, `checkout/simulate`, `test/checkout.spec.ts` |
| 2 | Real Cashfree money | **code done, waiting on credentials** | 90 % | signed webhook, refunds, trial, upgrade proration, coupons, nightly sweep; `CASHFREE_MODE=stub` and placeholder keys in `.env` |
| 3 | Prices as data, edited by an admin | **done** | 100 % | `tier_price` + `price.service.ts` + AdminJS grid (D-251), 9-month dropped (D-248), `test/price-service.spec.ts` |
| 4 | Google Play in-app purchases | **code done, waiting on Play Console** | 80 % | server: verify + RTDN + grants + User Choice reporting, 16 tests in `test/store-purchases.spec.ts`. App: `PlayStoreGateway` + paywall Play branch (D-252), `test/billing_gateway_test.dart` |
| 5 | Apple App Store in-app purchases | **code done, waiting on App Store Connect** | 75 % | `appstore/verify` + notifications v2 + `app-store.client.ts`, `test/app-store-purchases.spec.ts`; app shares `InAppStoreGateway` (D-253) |
| 6 | Money operations (invoices, payouts, tax) | **code done, waiting on the CA** | 85 % | payouts + statements + reconciliation (D-254); in-app KYC only when a payout is due, GST invoices + credit notes (D-255); TDS rate, SAC code and GST registration need the CA |

**Overall: the code is done on both sides for Cashfree, Play and the App Store.** What is left is
console setup, credentials, device testing, and the tax work with the CA. Nothing can take real money
until those are done.

---

## Phase 1 — Cashfree checkout on stub rails · done

**Done:** tiers and entitlements (`tiers.ts`, `GET /billing/entitlements`), the `payment_order` row,
`POST /billing/checkout`, and `checkout/simulate` standing in for the webhook so the whole purchase
path runs before any credentials exist. The app has the paywall, plan cards, comparison sheet and
`BillingController`; `payments_mode` tells it which rails it is on and the button says "stub" rather
than implying a payment (D-196).

**Remaining:** nothing.

## Phase 2 — Real Cashfree money · code done, blocked on credentials

**Done:** order creation and refunds against Cashfree (`cashfree.client.ts`), the webhook with
signature verification (`cashfree-webhook.controller.ts`, `test/cashfree-signature.spec.ts`), the
three modes stub/sandbox/production (`test/cashfree-mode.spec.ts`), free trial once per number,
cancel-renewal, upgrade quote + proration, refunds (`test/billing-upgrade-refund.spec.ts`), coupons
(`test/coupons.spec.ts`), the subscription lifecycle and the nightly sweep with its scheduler, and
the native Cashfree SDK wired into the app (`flutter_cashfree_pg_sdk`, `cashfree_gateway.dart`).
Which app may even be offered Cashfree is decided server-side (D-249): iOS never, Android only with
User Choice Billing, stub always.

**Remaining:**
1. Real Cashfree credentials (`CASHFREE_APP_ID`, `CASHFREE_SECRET_KEY`) and `CASHFREE_MODE=sandbox`,
   then `production`. Today both are `TEST_..._REPLACE_ME`.
2. The webhook URL registered in the Cashfree dashboard, reachable on the live server over HTTPS.
3. One real sandbox payment end to end: order → gateway → webhook → subscription active.
4. RBI e-mandate/AFA behaviour above `AFA_THRESHOLD_PAISE` (₹15,000) has never been exercised
   against a real mandate.

## Phase 3 — Prices as data · done

**Done:** `tier_price` holds the price per tier and length, seeded from the old constants and edited
in the admin panel, so a price change is not a deploy (D-251). `GET /billing/prices` feeds the
paywall. 9-month plans are gone from the grid (D-248).

**Remaining:** nothing in code. Someone still has to set the real prices in the panel before launch.

## Phase 4 — Google Play in-app purchases · code done, waiting on Play Console

**Done (server):** `POST /billing/play/verify` re-reads the purchase from Google before anything is
unlocked; real-time developer notifications arrive over Pub/Sub behind a shared secret and are
treated as a hint, never as truth; `store-grant.service.ts` puts the store's own expiry on the
subscription row; product ids map to tier × length (`p1m`, `p3m`, `p6m`, `p1y`); a token claimed by
another account is refused; the same token twice is one row; a running trial closes when a store
plan starts; a Cashfree sale chosen through User Choice Billing is reported back to Google. Sixteen
tests cover it, plus the `1759100000000-StorePurchases` migration.

**Remaining:**
1. ~~App store billing~~ **done 30 Sep 2026 (D-252):** `in_app_purchase` +
   `lib/data/datasources/remote/play_store_gateway.dart`; the paywall buys the server-named base plan
   with the account token, every token goes to `play/verify`, unconfirmed purchases are re-sent once
   per launch. Not yet run on a device.
2. Play Console setup: the two subscriptions with four base plans each, prices per country, and a
   service account with Play Developer API access.
3. Pub/Sub topic for notifications, and the push URL with `GOOGLE_PLAY_RTDN_TOKEN` on it.
4. User Choice Billing enrolment before `CASHFREE_ANDROID_ENABLED=true` means anything.
5. A real purchase, renewal, cancellation, refund and grace period tested on a device against the
   Play sandbox — none of this has touched Google yet.

## Phase 5 — Apple App Store in-app purchases · code done, waiting on App Store Connect

**Done (30 Sep 2026, D-253):** `POST /billing/appstore/verify` checks the StoreKit 2 signed
transaction against Apple's root certificates, re-reads the subscription from the App Store Server
API, and grants through the same `StoreGrantService` as Play. Notifications v2 at
`POST /billing/appstore/notifications`. iOS gets `payments_mode: app_store` once configured. The app
buys through the same `InAppStoreGateway` as Play, with the account token as `appAccountToken`.
Tests: `api/test/app-store-purchases.spec.ts`, `test/billing_gateway_test.dart`.

**Remaining:**
1. App Store Connect: one subscription group, eight products `eatzify.<basic|pro>.<p1m|p3m|p6m|p1y>`,
   prices, and the Paid Apps agreement signed.
2. An In-App Purchase API key (.p8) and the server env: `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`,
   `APP_STORE_PRIVATE_KEY_FILE`, `APP_STORE_ROOT_CERTS_DIR` (Apple's `.cer` roots from
   apple.com/certificateauthority), `APP_STORE_ENVIRONMENT`, and `APP_STORE_APP_APPLE_ID` for
   Production. `APP_STORE_BUNDLE_ID` defaults to `app.eatzify`.
3. The notification URL (`https://<api>/api/v1/billing/appstore/notifications`) set in App Store
   Connect for sandbox and production.
4. A sandbox purchase, renewal, cancellation and refund on a real iPhone.

## Phase 6 — Money operations · payouts built, waiting on the CA

**Done:** refunds through Cashfree, the GST split, the commission ledger. **30 Sep 2026 (D-254):**
monthly payout run on the 1st (₹1,000 minimum, rolls forward), KYC gate (last four of PAN and bank
only) with a 7-day freeze after a bank change, TDS from a dated `tds_rate` table, admin mark-paid
with UTR (TOTP + audit), cancel, CSV statement per payout for the partner, nightly ledger-vs-payout
reconciliation. Also fixed: refunds never reversed commissions (`reverseForOrder` looked for a
status no row has).

**Remaining:**
1. **The CA:** the 194H TDS rate, entered with `POST /admin/tds-rates`; until then the run refuses.
   Whether the annual threshold changes the flat per-payout deduction, and GST on commission
   (registered vs reverse charge).
2. ~~Partner KYC form~~ and ~~GST invoices~~ **done (D-255).** KYC appears in the app only once
   ₹1,000+ is due. Invoices issue once `GST_SELLER_*` and `GST_SAC_CODE` are set (from the CA), and
   `KYC_FIELD_KEY` must be set for KYC to save.
3. Revenue reconciliation against Cashfree/Play/Apple reports; B2B invoices (buyer GSTIN, IGST).
4. Dunning copy for a failed renewal beyond what the sweep sends.

---

## Two config mistakes found while writing this

1. **The Play env keys in `api/.env.example` cannot configure the code.** The code reads
   `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE` (a path) and `GOOGLE_PLAY_RTDN_TOKEN`; the example file offers
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (base64) and `PLAY_RTDN_TOPIC`. Anyone following the example
   ends up with Play unconfigured and `STORE_NOT_CONFIGURED` at runtime.
2. **`GOOGLE_PLAY_PACKAGE_NAME=app.eatzify` in the example is the iOS bundle id.** The Android
   application id is `com.zynthovo.eatzify`, which is what the code defaults to. Wrong here means
   every purchase verification is for the wrong app.

Neither is fixed yet; both are one-line edits once someone confirms the intended ids.

## Suggested order

1. Fix the two config mistakes above (minutes).
2. Cashfree sandbox credentials and one real end-to-end payment (Phase 2 finishes).
3. ~~Store billing in the app~~ (done). Play Console products, then a device purchase against the
   Play sandbox (Phase 4 finishes). Android can then ship a paid tier.
4. ~~Decide on iOS~~ Phase 5 built (D-253). App Store Connect products + API key, then a sandbox
   purchase on an iPhone.
5. ~~Payouts~~ built (D-254). The TDS rate and GST treatment from the CA (Phase 6).

## How to re-check this

```bash
cd health_pro/api && npm test                  # billing + store suites
grep -n "CASHFREE_MODE\|CASHFREE_APP_ID" .env  # stub or real?
grep -nE "in_app_purchase|purchases_flutter" ../pubspec.yaml   # empty = Phase 4 app side missing
grep -rn "payments plan, Phase" src | sort     # what the code thinks it belongs to
```
