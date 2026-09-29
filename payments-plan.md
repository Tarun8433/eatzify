# Payments — Play Billing, Apple IAP and Cashfree, with the user choosing

A box is ticked only after its check has actually passed.

## Decisions (product owner, 29 Sept 2026)

| Topic | Decision |
|---|---|
| Distribution | **Open testing** on Play. The account is an Organisation, so the 12-tester / 14-day closed-test rule does not apply |
| Android | **User Choice Billing**: Google Play Billing *and* Cashfree side by side; the user picks at checkout |
| iOS | **Apple in-app purchase only**. Apple does not allow another processor for digital subscriptions in India, so Cashfree is not offered on iPhone |
| 9-month plans | **Dropped everywhere**: 1, 3, 6 and 12 months only (Play and Apple cannot sell 9 months) |
| Prices | **Cashfree prices set in the admin panel.** Play and App Store prices are set in their consoles: the stores own what they charge, and the app must show the store's own price string |

## Why this shape

- **Activation is server-side on every rail.** Cashfree's verified webhook, Google's purchase check,
  Apple's signed transaction — the app never unlocks anything itself (docs/11 §5, rule 3).
- **One entitlement per person, whatever they paid with.** A Play subscription unlocks the same tier
  on iPhone after sign-in, because entitlements live on the account, not the store.
- **Play policy:** offering Cashfree for a digital subscription on Android is only allowed once the
  app is **enrolled in User Choice Billing**. Until then the Android paywall must not show Cashfree.

## Needs you (nothing below can start without these)

- [ ] **HTTPS domain live** — `eatzify-api.zynthovo.com`. Google's and Apple's purchase notifications, and Cashfree's webhook, only call HTTPS
- [ ] **Play Console → Monetisation setup → Alternative billing**: enrol in User Choice Billing (India)
- [ ] **Play Console → Subscriptions**: `basic` and `pro`, each with base plans `p1m`, `p3m`, `p6m`, `p1y`
- [ ] **Google Cloud service account** with Play Developer API access, JSON key on the server (never in git)
- [ ] **Play → Real-time developer notifications**: a Pub/Sub topic pushing to the API
- [ ] **Apple Developer Program, Organisation enrolment** (needs a D-U-N-S number)
- [ ] **App Store Connect**: one subscription group, `basic` and `pro` at 1/3/6/12 months; an App Store Connect API key; Server Notifications v2 URL
- [ ] **Store listing complete** for open testing: privacy policy URL (the site, live), data safety form, content rating, target audience, app-access instructions for the reviewer

## Tracker

### Phase 0 — Decisions and docs
- [ ] ADR-014 in `docs/07`: three payment rails, server-side activation, UCB on Android, IAP-only on iOS
- [x] DECISIONS: D-248 drop 9 months · D-249 which app may be offered Cashfree

### Phase 1 — Open testing (Play Console)
- [x] Hide the Cashfree option on Android until UCB enrolment is approved (server flag)
- [ ] Reviewer access: a documented way to sign in (the OTP flow needs a real SMS provider first — see "Blocking")
- [ ] Open testing track: countries, release, rollout

> **Phases 1–2 verified 2026-09-29:** API `npx jest` 708/708 (a table test pins every platform × mode × switch); app `flutter test` 902/902.

### Phase 2 — Drop 9-month plans
- [x] `api/src/billing/tiers.ts`, checkout validation, tests
- [x] Paywall, the website's pricing page, `docs/11`

### Phase 3 — Cashfree prices from the admin panel
- [ ] `tier_price` table, migration seeded from today's prices
- [ ] AdminJS resource; checkout charges the stored price; cache with a short TTL
- [ ] Tests: a price changed in the admin is what the next checkout charges

### Phase 4 — Server: verifying store purchases
- [ ] `subscription.source` (`cashfree` · `play` · `app_store`) and store transaction ids
- [ ] Google: verify a purchase token, **acknowledge within 3 days** (Play refunds unacknowledged purchases), grant the tier
- [ ] Google: RTDN endpoint for renewals, cancellations, refunds, grace, holds
- [ ] Google UCB: report each Cashfree-chosen purchase through the external-transactions API
- [ ] Apple: verify signed transactions (App Store Server API), grant the tier
- [ ] Apple: Server Notifications v2 endpoint
- [ ] Idempotent on transaction id everywhere; tests for each path

### Phase 5 — App, Android
- [ ] `in_app_purchase` (Billing Library 8), product lookup, store price strings shown as-is
- [ ] User Choice Billing: Play's own choice screen → Play path, or → Cashfree path with the external-transaction token sent to the server
- [ ] Restore purchases; pending purchases; tests with a fake store

### Phase 6 — App, iOS
- [ ] StoreKit through `in_app_purchase`; Cashfree hidden on iOS
- [ ] Restore purchases button (App Review requires it); tests

### Phase 7 — End-to-end in sandbox
- [ ] Play licence testers: buy, renew, cancel, refund
- [ ] Apple sandbox: buy, renew, cancel, refund
- [ ] Cashfree sandbox through the UCB choice

## Blocking, before any public release

- **OTP `000000` signs in as anyone** — no SMS provider is wired. Open testing makes the app public; this must be fixed first.
- **The Android app sells through Cashfree today without UCB enrolment** — a Play payments-policy violation once the app is public. Phase 1's server flag hides it until enrolment is approved.
