# 03 — Domain Model & Glossary

Every ambiguous word in the original spec gets exactly one meaning here. If code uses one of these
words differently, the code is wrong.

## 1. Core entities

| Entity | Definition | Notes |
|---|---|---|
| **User** | One human account. Has exactly one active `role_set`. | A coach is a User with the coach role, not a separate table. |
| **Profile** | Slow-changing identity: DOB, sex at birth, height. | Height changes ~never. Separate from measurements. |
| **HealthProfile** | Declared conditions, allergies, diet preference, activity level, lifestyle. Versioned. | Every change writes a new version; plans reference the version they were built from. |
| **Measurement** | A timestamped observation: weight, waist, BP, HbA1c. | Never overwrite. Append. |
| **Goal** | Direction (`fat_loss` \| `muscle_gain` \| `maintenance`) + optional target weight + target date. | One active goal at a time. |
| **RulePack** | Immutable, versioned set of engine constants and decision tables. | `1.0.0`. Semver. Bump minor for constant changes, major for structural. |
| **DietPlan** | A generated plan for a user, for a date range, from one rule pack, with a decision trace. | Immutable once issued. Edits create a new `revision`. |
| **PlanDay → Meal → MealItem** | The plan's content tree. | `MealItem` references a `Food` or `Recipe` plus a quantity. |
| **Food** | An atomic nutrition record per 100 g edible portion. | Sourced from IFCT/INDB/manual. Traceable. |
| **Recipe** | A composite dish with ingredients and a yield factor. | Where "dal tadka" lives. |
| **HouseholdMeasure** | A named portion for a food: `1 katori = 150 g`. | Users think in katoris, not grams. Non-negotiable for India. |
| **FoodLog** | What the user actually ate. | Distinct from the plan. Compliance = log ∩ plan. |
| **PlanTier** | `FREE` \| `BASIC` \| `PRO`. (COACHING is a *service*, not a tier — see doc 01 §3.) | |
| **Subscription** | A user's purchase of a PlanTier for a term, with a lifecycle state machine. | |
| **Entitlement** | A resolved boolean/quota capability, e.g. `plan.regenerate_per_day = 3`. | Server-resolved. The app never computes entitlements. |
| **CoachAssignment** | A link between a coach and a client, with a consent grant and a scope. | The join carries the permission, not the user row. |
| **Partner** | An entity earning commission on referred purchases. A Partner may or may not be a Coach. | |
| **Attribution** | The immutable record of which partner referred a user. | Written once, at signup. |
| **CommissionEntry** | A ledger line: accrued, held, payable, paid, or reversed. | Double-entry discipline; never mutate, only append offsetting entries. |
| **Consent** | A record of a specific purpose the user agreed to, with timestamp, version, and scope. | The legal spine of the product. |

## 2. Onboarding input contract

```
age_years        int      18..99          (derived from dob; <18 → reject)
sex_at_birth     enum     male | female | intersex_prefer_not_say
height_cm        int      120..220
weight_kg        decimal  30.0..250.0
goal             enum     fat_loss | muscle_gain | maintenance
activity_level   enum     sedentary | light | moderate | heavy
conditions       set      none | type2_diabetes | prediabetes | hypertension |
                          hypothyroid | hyperthyroid | pcos | post_surgery |
                          ckd | pregnancy | lactation | other_declared
food_preference  enum     veg | non_veg | eggetarian | jain | vegan
food_allergies   set      milk | wheat_gluten | soy | peanut | tree_nut | egg |
                          fish | shellfish | sesame | mustard | other
budget_tier      enum     low | medium | premium
lifestyle        enum     office | student | night_shift | flexible | home
meal_count       enum     3 | 4 | 5_6
```

Notes on things the original spec got wrong or omitted:
- **`gender` → `sex_at_birth`.** The BMR equation needs biological sex. Gender identity is a separate
  (optional, never-required) field and must not drive the equation.
- **`pregnancy` / `lactation` were missing entirely.** They are hard clinician gates (doc 05).
- **`ckd` was missing.** It is the single most important contraindication for a high-protein engine.
- **Jain and vegan were missing** from food preference. Both matter in your market. Jain additionally
  excludes root vegetables — that's a food tag, not a preference flag.
- **Allergies must be food allergies.** The current app has a free-text field collecting
  "Dust, pollution", which is clinically useless here and creates a health-data liability for no benefit.
- **`none` in conditions is exclusive.** Selecting it clears the rest. Enforce in the DTO.

## 3. Vocabulary corrections from the original spec

| Spec word | Problem | Use instead |
|---|---|---|
| "PCOD" | Outdated term | `pcos` (Polycystic Ovary Syndrome) |
| "Diet chart" | Ambiguous (template? plan? PDF?) | `DietPlan` (data) vs `PlanExport` (PDF artifact) |
| "Premium" | Used for three different things: a tier, a badge, a food audience | `PlanTier.PRO`, `verified_badge`, — (delete the third) |
| "Coach" / "Partner" | Used interchangeably | `Coach` = manages clients. `Partner` = earns commission. Overlapping but distinct roles. |
| "Plan" | Means both diet plan and subscription plan | `DietPlan` vs `PlanTier`/`Subscription` |
| "Target Audience" (on a food) | Content tiering in the wrong layer | Delete. Use `Entitlement`. |
| "Category / Tags" | Two overlapping mechanisms | One `tags` taxonomy with namespaces: `group:*`, `gi:*`, `cost:*`, `pref:*`, `cond:*` |
| "Verified Coach" / "Certified Coach" | Implies accreditation you cannot grant | `Verified Partner` + explicit `verified_attributes` |

## 4. Tag taxonomy (namespaced, closed vocabulary)

```
group:cereal|pulse|dairy|veg|fruit|nut_seed|meat|fish|egg|fat_oil|sugar|beverage|prepared
gi:low|medium|high              (low ≤55, medium 56–69, high ≥70)
cost:low|medium|premium
pref:veg|non_veg|egg|jain|vegan
cond:diabetes_ok|hypertension_ok|pcos_ok|ckd_caution|easy_digest|post_surgery_ok
prep:raw|boiled|fried|roasted|fermented
region:north|south|east|west|northeast|pan_india
attr:high_protein|high_fibre|low_sodium|low_carb|iron_rich|calcium_rich
```

Rules: tags are additive, never contradictory (`gi:*` is single-valued). `cond:*_ok` means "permitted
by the rule pack for that condition" and is **derived** by a nightly job from nutrient thresholds —
never hand-typed by an admin. That's how you stop someone tagging jalebi `cond:diabetes_ok`.

## 5. State machines

**Subscription:** `trialing → active → past_due → grace → expired`, with `cancelled` reachable from
`trialing|active|past_due|grace`, and `active → active` on renewal. `upgraded` is a transition that
closes one subscription and opens another with a proration credit.

**DietPlan:** `draft → issued → active → superseded | expired`. Coach override on an `active` plan
creates `revision+1` and supersedes the previous.

**CommissionEntry:** `accrued → held (T+7 refund window) → payable → paid`, or
`accrued|held → reversed` on refund/chargeback.

**Ticket:** `new → open → waiting_user → resolved → closed`, reopenable within 7 days.

**CoachAssignment:** `invited → active → paused → ended`. Consent grant expiry forces `→ paused`.

## 6. Time and the day boundary

- Storage: `TIMESTAMPTZ`, UTC.
- Display and all business-day logic: `Asia/Kolkata`, fixed (+05:30, no DST — one fewer bug than most).
- **A "diary day" runs 04:00 IST → 03:59 IST next day.** A meal logged at 00:30 belongs to the
  previous diary day. This is not optional in a market with late dinners and night-shift users, and
  it must be one shared function (`diaryDateFor(timestamp)`) used by app, API and reports. Getting
  this wrong produces the classic "my log vanished" bug.
- Streaks and adherence use diary days, not calendar days.

## 7. Units

| Quantity | Stored as | Displayed as |
|---|---|---|
| Energy | integer kcal | kcal |
| Macros | grams, 1 decimal | rounded integer grams |
| Sodium | mg | mg (and "≈ x g salt" where salt is the more intuitive unit) |
| Weight | kg, 1 decimal | kg, 1 decimal |
| Height | cm, integer | cm, and ft/in as a secondary display |
| Money | integer paise | ₹ with Indian digit grouping (₹1,24,560 — not ₹124,560) |
| Food quantity | grams | household measure primary, grams secondary |
