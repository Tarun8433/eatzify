# 15 — UX / QA Audit of the Current Build

Findings from the 20 screenshots supplied. Severity: **P0** ships-blocking · **P1** fix before launch ·
**P2** fix soon · **P3** polish.

## A. Information architecture

| ID | Sev | Finding |
|---|---|---|
| D-01 | P0 | **Four different bottom navigation bars** across screens (Home/Diary/+/Reports/More · Home/Log/Trends/Profile · Home/Log/Trends/Log Meal · Tracker/Diet Plan/Progress). Consolidate to one shell (doc 14 §1). |
| D-02 | P1 | A hamburger "Menu" bottom sheet with nine tiles duplicates the tab bar. Delete it. |
| D-03 | P1 | Inconsistent header pattern: some screens have a top-left hamburger, others a back arrow + "Menu" pill + title. Pick one. |
| D-04 | P2 | Two different logout affordances (menu sheet footer and Settings → Account). One. |

## B. Branding and build hygiene

| ID | Sev | Finding |
|---|---|---|
| D-05 | P0 | Coach dashboard shares `https://fitfuel.app/coach/prashant` while the app is branded **Eatzify**. Two brands in one product. |
| D-06 | P1 | Footer reads "© 2024 Eatzify. All rights reserved." while in-app dates read 2026. Make the year a build constant. |
| D-07 | P1 | "Version 1.0.0" hardcoded in two places; pull from package info. |

## C. Data integrity

| ID | Sev | Finding |
|---|---|---|
| D-08 | P0 | **Nutrition DB contains only two rows, both invalid.** "CHAUHAN4" states 34 kcal but P4/C5/F1 derives to 45 kcal (32 % off). "vishwash" states 134 kcal vs 107 derived (25 % off). Add the Atwater constraint (doc 08 §4) and a review workflow. |
| D-09 | P0 | Placeholder/test names ("CHAUHAN4", "vishwash", "Testing", "VISHWASH / GOOD EVENING" as a sent notification) are in what appears to be a live database. Separate demo data with `is_demo` and never seed prod. |
| D-10 | P0 | **Progress shows "Change: −30.0 kg"** for a user whose current weight is 95 kg, with calendar entries of 65.0, 58.0, 65.0 on three consecutive days. The delta calculation and the entry validation are both wrong. One weight per diary day + plausibility confirm + MA7 display. |
| D-11 | P1 | Admin dashboard shows ₹18,450 today / ₹1,24,560 this month / 32 diet plans created against **4 total users and 1 active subscription**. Mock metrics rendered as real. |
| D-12 | P1 | Two separate "All Users" admin screens with different layouts and different stat cards (one shows "Avg. Weight Loss 2.4 kg", the other "Expiring Soon"). Duplicate implementations of the same feature. |
| D-13 | P2 | Coach management screen shows "Total Clients 256" while the four listed coaches sum to 150. Roll-ups computed from different sources. |

## D. The diet engine contradicts its own spec

| ID | Sev | Finding |
|---|---|---|
| D-14 | **P0** | Profile: male, 29, 173 cm, 95 kg, moderate, goal `lose_weight`. Daily target shown: **2,431 kcal**, macros **P 122 g / C 334 g / F 68 g**. Your own spec (Mifflin → ×1.55 → −20 %, protein 1.5–2.0 g/kg) yields **2,345 kcal and 136–190 g protein**. The app is 86 kcal high and **14–68 g short on protein**, with carbs at 55 % of energy on a fat-loss plan. The engine is not implementing the written rules. |
| D-15 | P0 | Protein appears to be computed as a fixed 20 % of energy rather than g/kg body weight. That is the single most consequential bug in the product. |
| D-16 | P1 | Water target hardcoded at 3 L for all users (should be ~33 ml/kg → 3.1 L here, coincidentally close, wrong in general). |
| D-17 | P1 | Step goal hardcoded at 10,000 regardless of profile. |
| D-18 | P1 | No visible protein-per-meal distribution; meals are just "Log Meal" buttons with no targets attached. |

## E. Safety and tone

| ID | Sev | Finding |
|---|---|---|
| D-19 | **P0** | Profile displays **"BMI Status: Obese"** as a status chip. Replace with the number plus neutral context (doc 05 §6). |
| D-20 | **P0** | Progress calendar marks past days red with a "**Missed**" legend. Shame mechanic in a calorie app. Change to neutral "not logged". |
| D-21 | P0 | No visible medical disclaimer on any plan or profile screen. Required (doc 05 §7). |
| D-22 | P0 | `post_surgery` and disease conditions are selectable with no clinician gate anywhere in the flow. |
| D-23 | P1 | Admin can target push notifications by **disease/condition** for commercial content ("Today new offer", type URGENT). Purpose-limitation and platform-policy problem (doc 13 §5). |
| D-24 | P1 | Profile collects **"Allergies: Dust, pollution"** — environmental allergens in a diet app. Restrict to a closed food-allergen list. |
| D-25 | P2 | "URGENT" notification type used for a promotional offer. Reserve urgency for service/clinical messages. |

## F. Privacy

| ID | Sev | Finding |
|---|---|---|
| D-26 | P0 | Admin user list shows full emails and phone numbers with an unrestricted **"Export CSV"** button. Mask by default; audited reveal; super-admin-only export with a stated reason (doc 10 §4). |
| D-27 | P1 | Coach management screen exposes each coach's phone, email and revenue in a list view — fine for you, but confirm no coach-level role can reach this screen. |
| D-28 | P1 | Admin ticket view shows the client's full email and phone beside the chat. Mask to last 4 unless revealed. |

## G. Subscription screen

| ID | Sev | Finding |
|---|---|---|
| D-29 | P1 | "Upgrade to Premium / Go Premium" banner renders **above an active Premium Yearly subscription**. Mutually exclusive states shown together. |
| D-30 | P1 | "Auto-renew: Disabled" shown next to a "Cancel Subscription" button. If auto-renew is off, the action should be "Renew now". |
| D-31 | P2 | "7-Day Money Back Guarantee — no questions asked" promises a mechanism Google controls for Play purchases (doc 11 §9). |

## H. Polish

- Emoji used as iconography throughout (🌞 lunch, 🥜 snacks, 😎 avatar, 🎂 age, 📏 height). Inconsistent
  across OS versions; replace with one icon set.
- Raw enum values shown to users: `lose_weight`, `moderate`, `vegetarian`.
- "Hello, Fit Warrior!" — a generic name where the user's actual name is available.
- Reminders: hourly presets only, no custom time; "Enable Reminders" on while "No reminders set".
- Empty states are text-only ("Start logging foods to get personalized insights") with no action button.
- Insights card is a decorative chart with no data behind it.
- Two of the 20 screenshots supplied are byte-identical duplicates (Coaches Management) — worth
  checking your screenshot/QA process too.

## Fix order

**P0 batch 1 (engine + safety):** D-14, D-15, D-19, D-20, D-21, D-22
**P0 batch 2 (data integrity):** D-08, D-09, D-10, D-26
**P0 batch 3 (IA):** D-01, D-05
Then P1s in the order above. Nothing new ships until batch 1 is closed.
