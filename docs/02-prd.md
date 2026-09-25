# 02 — Product Requirements

## 1. Personas

**P1 — Coach (primary buyer).** 26–40, certified or self-taught, 20–60 clients, ₹2–8 k/client/month,
runs everything on WhatsApp. Wants: fewer hours per client, no client leakage, professional
appearance, reliable payouts. Fears: losing client relationships to the platform, data leaking to
competitors, looking unprofessional if the app breaks in front of a client.

**P2 — Client (end user).** 24–45, urban/tier-2, BMI 26–34, goal fat loss, vegetarian or eggetarian,
office lifestyle, one of {none, PCOS, prediabetes, thyroid, high BP}. Cooks or is cooked for at home,
eats out 2–4×/week. Wants: to be told what to eat with foods they actually eat. Fears: being judged.
Abandons at: complicated logging, foods they've never heard of, seeing "Obese" on a dashboard.

**P3 — Admin (you / ops).** Needs: content moderation of the food DB, coach verification, ticket
handling, payout runs, and a metrics view that isn't polluted with demo data.

**P4 — Gym owner (partner, secondary).** Onboards their trainers, wants roll-up numbers and one payout.

## 2. Scope — the MVP cut line

### In (v1)
| Area | Included |
|---|---|
| Client onboarding | Profile form (doc 03 §2), consent capture, condition declaration, safety gates |
| Diet engine | Rule-based generation, v1 rule pack, explainability trace, coach override |
| Food DB | ~600 seeded items (INDB-derived) + household measures + admin CRUD with validation |
| Logging | Food (search + recent + favourites), water, weight, steps (Health Connect / HealthKit / manual) |
| Progress | Weight trend, adherence %, macro rings, weekly summary |
| Coach surface | Client list, client detail, plan view/override, check-in queue, alerts, in-app chat |
| Partner | Referral code + link, attribution, earnings dashboard, payout requests |
| Billing | BASIC + PRO, Play Billing + Razorpay (web), trial, upgrade proration, renewal reminders |
| Admin | Users, coaches, food DB, tickets, notifications (non-clinical targeting only), audit log |
| Compliance | Consent ledger, data export, deletion request flow, retention jobs |

### Out (v1) — deliberately
AI auto-adjustment · behaviour analysis · progress prediction · workout plans ·
transformation programme storefront · community/groups · COACHING plan as a first-party service ·
web app · iOS launch (Android first) · Hindi UI (ship the i18n *scaffolding*, not the translation) ·
gamification/challenges · wearable integrations beyond steps.

Meal-photo **scanning** moved into v1 by D-238, in the shape `docs/04` §11 specifies: the photo is matched to
foods in our own table, the user confirms dish and portion, nothing is auto-logged, and nutrition always
comes from the food row — never from the model.

Each of these is in doc 17 with a trigger condition for revisiting it.

### The three features you should cut permanently
1. **"Behavior analysis (user skip karta hai kya?)"** as a standalone feature. It's a report, not a
   product. Fold it into the coach's client detail as "logged 4/7 days".
2. **"Progress prediction: agar aise chala to 30 days me result kya hoga"** as a headline promise. A
   linear extrapolation of noisy weight data will be wrong and will be quoted back at you. If you keep
   it, present a *range* with an explicit "this is an estimate, not a promise" and never show it to a
   user whose trend is negative.
3. **Per-food "Target Audience: Premium Users"** (visible in your admin nutrition screen). Content
   tiering does not belong on the food row. Entitlements belong in the entitlement layer. Doc 08 §5.

## 3. Functional requirements (numbered — reference these in tickets)

### FR-1 Onboarding & profile
- FR-1.1 Collect: DOB, sex at birth, height (cm), weight (kg), goal, activity level, food preference,
  meal count preference, lifestyle, budget tier, allergies (food only), conditions (multi-select).
- FR-1.2 Reject onboarding if computed age < 18, with a plain, non-punitive message.
- FR-1.3 If sex = female and age 18–50, ask pregnancy/lactation status. If yes → clinician gate
  (doc 05 §3). **This is missing from the current spec and is a hard requirement.**
- FR-1.4 Height and weight inputs validated to plausible ranges (120–220 cm, 30–250 kg) with a
  confirm step on outliers.
- FR-1.5 Goal weight, if collected, rejected if it implies BMI < 18.5.
- FR-1.6 Separate food allergies from environmental allergies. The current profile shows
  "Allergies: Dust, pollution" in a diet app — that field is being misused.
- FR-1.7 Present itemised consent (doc 13 §3) before any health field is stored.

### FR-2 Diet plan generation
- FR-2.1 Generate a full-day plan: meals, items, quantities in grams **and** household measures,
  per-meal and per-day kcal/protein/carb/fat/fibre/sodium.
- FR-2.2 Every plan stores `rule_pack_version`, input snapshot, and a decision trace.
- FR-2.3 Apply medical overrides after calorie calculation, in the documented order (doc 04 §5).
- FR-2.4 Offer ≥2 alternates per item, matched within ±10 % kcal and ±5 g protein.
- FR-2.5 Coach can override any item, meal, or the whole day; overrides are versioned and attributed.
- FR-2.6 Regeneration is explicit and rate-limited (max 3/day/user) — plans are not slot machines.
- FR-2.7 Plan is readable offline once fetched.

### FR-3 Logging
- FR-3.1 Food log: search (name + regional synonyms), recents, favourites, custom food, quantity in
  household measures with gram equivalents.
- FR-3.2 Water log: increments, daily target from rule pack (not a hardcoded 3 L).
- FR-3.3 Weight log: one per day max; delta > 3 kg from the last entry within 7 days triggers a
  confirm dialog (this is what produced the "−30.0 kg" readout — doc 15 D-04).
- FR-3.4 Steps: read-only from Health Connect / HealthKit, with manual entry fallback and a visible
  data-source label.
- FR-3.5 Log entries editable/deletable for 48 h, then locked (audit integrity).

### FR-4 Progress
- FR-4.1 Weight trend using a 7-day moving average as the primary line; raw points secondary.
- FR-4.2 Adherence = days with ≥1 food log ÷ days since plan start, shown as a count not a shame badge.
- FR-4.3 No red "Missed" markers on past days in the calendar. Use neutral "not logged".
- FR-4.4 BMI shown with the number and the Indian cut-off context, never the bare word "Obese" as a
  status chip.

### FR-5 Coach surface
- FR-5.1 Coach sees only clients explicitly assigned to them, and only fields the client consented to
  (doc 10 matrix).
- FR-5.2 Check-in queue: clients with a due or overdue check-in, sorted by risk.
- FR-5.3 Alerts: no log ≥3 days, weight trend against goal, plan expiring, check-in missed.
- FR-5.4 Coach cannot export client PII. Full stop.
- FR-5.5 In-app chat with the client; messages retained per doc 13 retention table.

### FR-6 Billing
- FR-6.1 Plan catalogue and prices are server-driven, never hardcoded in the app.
- FR-6.2 Entitlements resolved server-side; the client caches them but never decides them.
- FR-6.3 Trial: 7 days, one per user identity (phone hash), converts unless cancelled, with a
  reminder 48 h before conversion (doc 11 §6).
- FR-6.4 Mid-term upgrade prorates remaining value (doc 11 §7 formula).
- FR-6.5 Expiry: notify at T-7, T-3, T-0; then downgrade to free, retaining data per retention policy.
- FR-6.6 Never show "Upgrade to Premium" to a user who holds an active premium subscription
  (doc 15 D-12).

### FR-7 Partner
- FR-7.1 Unique referral code + deep link per partner.
- FR-7.2 Attribution recorded at signup, immutable thereafter (doc 12 §2).
- FR-7.3 Commission ledger: accrual, hold period, reversal on refund, payout.
- FR-7.4 Partner sees aggregate earnings and *masked* client identity at Level 1 (doc 10).
- FR-7.5 Minimum payout ₹1,000; monthly cycle; TDS and GST handling per doc 12 §5.

### FR-8 Admin
- FR-8.1 Food CRUD with Atwater consistency validation (doc 08 §4) — reject rows where stated kcal
  deviates > 10 % from macro-derived kcal.
- FR-8.2 Food publishing workflow: draft → reviewed → published. Only published foods reach users.
- FR-8.3 Coach verification workflow with document upload and an explicit "what we verified" record.
- FR-8.4 Notifications: broadcast and segment, but condition-based targeting restricted to clinical
  content and logged (doc 13 §5).
- FR-8.5 Every admin read of a health field is written to the audit log.
- FR-8.6 Demo/seed data flagged `is_demo` and excluded from every metric.

## 4. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-1 | p95 API latency < 400 ms; plan generation < 800 ms server-side |
| NFR-2 | App cold start < 2.5 s on a 3-year-old mid-range Android |
| NFR-3 | Full offline read of today's plan, diary and profile; writes queue and sync |
| NFR-4 | APK < 30 MB; no font or image bundled that isn't used |
| NFR-5 | Health data encrypted at rest (column-level for conditions), TLS 1.3 in transit |
| NFR-6 | Nightly encrypted DB backup, 30-day retention, quarterly restore drill |
| NFR-7 | 99.5 % monthly availability target |
| NFR-8 | Every screen: loading, error, empty state. No infinite spinner. |
| NFR-9 | Touch targets ≥ 48 dp; contrast ≥ 4.5:1; supports 200 % font scale without clipping |
| NFR-10 | i18n-ready from day one (en, hi); no concatenated strings |
| NFR-11 | Audit log immutable, append-only, 3-year retention |

## 5. Acceptance criteria examples (write the rest in this shape)

**FR-2.1** — *Given* a 29-year-old male, 173 cm, 95 kg, moderate activity, fat-loss goal, vegetarian,
no conditions, 4 meals, *when* a plan is generated with rule pack v1.0.0, *then* the plan totals
2,345 kcal ± 2 %, protein 136 g ± 3 g, and every meal contains ≥ 20 g protein, and the response
includes `rule_pack_version: "1.0.0"` and a trace with ≥ 6 steps. (Full vector: doc 16 GV-01.)

**FR-1.2** — *Given* a DOB implying age 17 years 11 months, *when* the user submits onboarding,
*then* the API returns 422 `AGE_INELIGIBLE`, no profile row is created, no health field is persisted,
and the app shows the approved copy from doc 05 §7.

**FR-6.6** — *Given* a user with an active PRO subscription, *when* they open the Subscription screen,
*then* no upgrade banner renders, and the primary action is "Manage plan".
