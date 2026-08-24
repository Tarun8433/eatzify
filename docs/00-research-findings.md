# 00 — Research Findings

Everything here was verified against current sources in August 2026. Each finding ends with what it
changes in the build. Verify anything marked ⚠ before you commit engineering time to it.

---

## 1. Nutrition science baseline (India-specific)

**ICMR-NIN is the authority you must be able to cite.** Two documents matter:
- *Nutrient Requirements for Indians — RDA & EAR, 2020*
- *Dietary Guidelines for Indians, 2024* (17 guidelines, "My Plate for the Day" model)

Three things in them directly contradict fitness-industry defaults, including parts of your spec:

| ICMR-NIN position | Your spec says | Consequence |
|---|---|---|
| Protein RDA for healthy Indian adults is **0.83 g/kg/day** (EAR 0.66) | 1.5–2.2 g/kg | Your targets are 2–2.6× the national RDA. Defensible for training populations, but you must disclose it and cap it. See doc 05. |
| DGI 2024 **explicitly discourages protein supplements/concentrates** for muscle building, citing bone mineral loss and kidney risk with prolonged high intake | "Protein (Priority)" | Do not sell or recommend supplements from inside the app in v1. Reputational and regulatory exposure with zero revenue upside at your scale. |
| Indian body composition carries relatively more fat, producing a **lower measured BMR** than Western predictive equations suggest | Mifflin-St Jeor, unmodified | Mifflin is still the right default (best-validated), but expect systematic over-prediction. Doc 04 handles this with a conservative deficit cap rather than a fudge factor. |

**Diet planning should be based on EAR, not RDA** — RDA is intended for supervised supplementation of
deficient individuals. This matters for the micronutrient layer you will eventually add.

**What it changes:** rule pack gets an `authority` field per constant, citing ICMR-NIN or the sports-
nutrition literature. When a constant departs from ICMR, the app must be able to say so.

---

## 2. Food composition data — licensing is the trap

| Source | Coverage | Licence | Verdict |
|---|---|---|---|
| **IFCT 2017** (ICMR-NIN book) | 528–542 foods, 151 components, measured across six regions | The book itself is ICMR-NIN's | Gold standard for raw foods. Source of truth. |
| `ifct2017` / `@ifct2017/*` npm packages | Same data, queryable | **AGPL-3.0 since 1 May 2025** ⚠ | **Do not link this into your backend.** AGPL's network clause would reach your server code. Use the published tables as a data source, build your own loader. |
| **INDB** (Indian Nutrient Databank, 2024) | 1,095 food items + **1,014 composite recipes** | Open access, published in *Current Developments in Nutrition* | **This is your seed set.** Composite Indian recipes (dal, sabzi, biryani) are exactly what IFCT lacks and what your users log. Verify the exact reuse terms before shipping. ⚠ |
| Commercial vision APIs: Passio (2.5 M items, on-device + cloud, Flutter SDK), LogMeal, Foodvisor (enterprise agreement only) | Global, weak on Indian home food | Paid, token-based | For "photo se meal detect". None is reliable on ghar ka khana. See §3. |

**What it changes:** doc 08 defines a `foods` table with a `source` and `source_code` column so every
row is traceable to IFCT/INDB/manual. Kill the two junk rows currently in the DB ("CHAUHAN4",
"vishwash") — they will otherwise end up in production.

---

## 3. Photo meal detection — scope it down or it will eat the roadmap

Vision APIs identify dishes and estimate portions. On Indian home cooking they will confuse a
paneer sabzi with a chicken curry and guess portions from a plate they cannot judge depth on.
Accuracy expectations from the vendors themselves are dish-identification, not gram-accurate
nutrition.

**Recommended v1 shape:** photo → candidate list of 3–5 dishes from **your own** food DB → user picks
one and confirms a portion using a household-measure picker (katori / roti / spoon / glass). Never
auto-log from a photo. Log `confidence`, `was_corrected`, and the correction; that dataset is the
only thing that will let you improve this later.

---

## 4. Platform: Google Fit is being switched off

- Google Fit APIs (Android + REST) are **supported only until the end of 2026**. New developer
  signups closed 1 May 2024.
- Replacement for mobile step tracking: **Health Connect** (on-device, Android-only).
- Replacement for cloud/account integrations: **Google Health API** (successor to the Fitbit Web API,
  which itself turns down September 2026). Every scope on the Google Health API is **Restricted**,
  which triggers a privacy and security review before production access — apply early, the queue is
  the critical path, not the code.
- iOS: **HealthKit**, separately.
- Existing Google Fit history does **not** migrate automatically, and OAuth tokens do not carry over.

**What it changes:** your screenshots show a Google Fit-shaped step integration. That is a dead end.
Doc 06 specifies Health Connect (Android) + HealthKit (iOS) behind one `HealthDataSource` interface,
with manual step entry as the always-available fallback. Treat this as a P0 for the current build.

---

## 5. Platform: Google Play billing economics

- Play's service fee for **auto-renewing subscriptions is 15 %** and has been since January 2022.
- On 30 June 2026 Google split the service fee from a new billing fee — **but only in the US, UK and
  EEA**. India and the rest of the world **keep the existing fee structure until 30 September 2027**.
- **India specifically allows an alternative billing system alongside Play billing** (a CCI-driven
  concession). Using it reduces Play's service fee by **4 percentage points** — so 15 % becomes 11 %.
  It requires enrolment, a compliant choice screen, and reporting via the alternative billing APIs.
- Play Billing Library 9.0 shipped 19 May 2026.

**What it changes:** doc 11 models both routes. At your price points, alternative billing saves ~4 %
of gross but costs you a payment gateway integration, tax handling, and a choice screen. Not worth it
before roughly ₹15–20 lakh/year of in-app revenue; worth it after. Selling subscriptions on your own
website and honouring them in the app is the cheaper first move — but read Play's payments policy
carefully on steering.

---

## 6. Payments: RBI E-mandate Framework, 2026 — this breaks your coaching plans

Issued 21 April 2026, effective immediately, consolidating eight earlier circulars. For recurring
card / UPI / PPI auto-debits:

- Recurring debits **up to ₹15,000** need no per-transaction AFA (OTP) once the mandate is registered.
- Debits **above ₹15,000 require AFA every time.**
- The ₹1,00,000 relaxation applies only to insurance premiums, mutual funds/SIPs and credit card bills
  — **not** app subscriptions.
- Issuers must send a **pre-debit notification at least 24 hours before** every debit, and a
  post-debit confirmation after.
- Customers can pause a single debit, or modify/revoke the mandate, at any time (with AFA).

**What it changes:** look at your own price matrix:

| Plan | 12-month price | Auto-renew viable? |
|---|---|---|
| BASIC 12M | ₹1,799–2,499 | Yes, silent |
| PRO 12M | ₹4,499–5,999 | Yes, silent |
| COACHING 9M | ₹13,999–16,999 | **Borderline / breaks above ₹15,000** |
| COACHING 12M | ₹17,999–22,999 | **No. AFA required on every renewal.** |

So: coaching renewals must be designed as *assisted* renewals (notification → user completes AFA),
not silent ones. Or bill coaching monthly. Or sell coaching as a one-time non-renewing term. Decide
before you build the renewal job — doc 19 Q7.

---

## 7. Privacy: DPDP Act 2023 + DPDP Rules 2025

- Rules notified **13 November 2025** (G.S.R. 846(E)). Phased: Data Protection Board live immediately;
  Consent Manager provisions from **13 November 2026**; **all other substantive obligations from
  13 May 2027**.
- Requirements that hit you directly: itemised, standalone consent notices in plain language;
  purpose limitation and data minimisation; purpose-based retention timelines with **48 hours'
  notice before erasure**; breach notification to affected individuals and to the Board within
  **72 hours**; verifiable parental consent for children (hence: no under-18s).
- Penalties run to ₹250 crore per category and stack.

**What it changes:** you are a Data Fiduciary processing health data and then *sharing it with third
parties (coaches and partners) for commercial purposes*. That is the highest-risk pattern in your
whole design and it is currently implemented as an admin toggle. Doc 13 specifies a consent ledger,
per-grant scoping with expiry, and a full audit trail. Build it now; retrofitting consent into a live
user base is brutal.

Also: your admin "Send Notification" screen currently supports **targeting users by disease /
condition**. Using health data to segment marketing pushes is a purpose-limitation problem and a
Play policy problem. Doc 13 §5 restricts condition-based targeting to *clinical* content only.

---

## 8. Professional scope of practice

The National Commission for Allied and Healthcare Professions Act, 2021 brought nutritionists and
dietitians into a statutory framework; "nutritionist" as a term remains loosely used, and
qualification standards across India are heterogeneous.

Two consequences for your partner model:
- **"EATZIFY Certified Coach" is a claim you should not make.** You are not an accredited certifying
  body. Use "Eatzify Verified Partner" and publish exactly what you verified (identity, qualification
  document on file, agreement signed). Anything stronger invites both regulatory and consumer-protection
  attention. ⚠ Get a lawyer's read on this before launch.
- **Therapeutic diets for diabetes, CKD, post-surgery and PCOS are medical nutrition therapy.** An
  algorithm and a fitness coach are not the right delivery mechanism for them unaided. Doc 05 defines
  which conditions the engine may plan for, which require a clinician gate, and which are hard blocks.

---

## 9. Competitive shape (India, mid-2026)

Positioning reality check: HealthifyMe (AI coach "Ria" + human coaches, freemium, aggressive
discounting), Fittr (community + coach marketplace), Cult.fit (bundled with fitness), plus a long tail
of Instagram coaches selling PDF plans over WhatsApp.

That long tail is your actual opportunity and your partner model is aimed correctly at it — those
coaches have clients and no software. But note what it implies: **your buyer is the coach, not the
end user.** A coach-first B2B2C product has different priorities than a consumer app (client
management, white-label feel, payout reliability, WhatsApp-first comms). Your current build is a
consumer app with a coach screen bolted on. Doc 01 §4 asks you to pick.

---

## 10. Risk register (from the above)

| # | Risk | Sev | Mitigation | Doc |
|---|---|---|---|---|
| R1 | Google Fit shutdown breaks step tracking | High | Health Connect + HealthKit now | 06 |
| R2 | Health data shared with coaches without lawful consent | **Critical** | Consent ledger, scoped grants, audit | 13 |
| R3 | Engine produces unsafe targets (under-eating, high protein in undiagnosed CKD) | **Critical** | Hard floors, condition gates, clinician referral | 05 |
| R4 | Coaching auto-renew fails silently above ₹15,000 | High | Assisted renewal or monthly billing | 11 |
| R5 | Commission stack (40 % + 15 % + 18 % GST) makes coaching unprofitable | High | Re-tier commissions; cap on human-COGS plans | 12 |
| R6 | AGPL nutrition package linked into backend | Med | Own loader, data from IFCT/INDB | 08 |
| R7 | Photo detection accuracy destroys trust | Med | Confirm-before-log, never auto-log | 04 |
| R8 | "Certified Coach" claim challenged | Med | Rename to Verified Partner; legal review | 12 |
| R9 | Four navigation shells → users cannot form a mental model | Med | One shell, five tabs, enforced | 14 |
| R10 | Seeded demo data mixed with production metrics | Med | `is_demo` flag, separate env, no seed in prod | 18 |
