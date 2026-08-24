# 04 — Diet Engine Specification

**Package:** `packages/diet-engine` — pure, deterministic, no I/O.
**Governs:** FR-2.x. **Safety layer:** doc 05 (read it; it can veto anything here).
**Rule pack:** `config/rule-packs/v1.0.0.yaml`. Every number below lives there, not in code.

## 1. Contract

```
generatePlan(input: EngineInput, pack: RulePack) -> EngineOutput
```

`EngineInput` = onboarding contract (doc 03 §2) + latest weight + optional coach constraints.
`EngineOutput` = `{ targets, meals, alternates, warnings[], gates[], trace[], packVersion }`.

Determinism requirements: no `Date.now()`, no `Math.random()`, no locale-dependent formatting, no
floating-point accumulation in output (round only at the boundary, once, per §8). Food selection uses
a seeded PRNG where the seed is `hash(user_id + plan_date + packVersion)` so a plan is reproducible.

## 2. Pipeline

```
1  validate & normalise input
2  compute BMR
3  compute TDEE
4  apply goal adjustment              -> raw target
5  apply SAFETY FLOORS/CEILINGS       -> clamped target   [doc 05 §2 — cannot be skipped]
6  evaluate condition gates           -> may abort with gates[]
7  set protein (on adjusted weight)
8  set fat, fibre, sodium, sugar caps
9  carbs = remainder
10 apply medical overrides (ordered)  -> constraint set
11 build food candidate pool (filters)
12 distribute targets across meals
13 fill meals (greedy + repair)
14 pick alternates
15 round, validate totals, emit trace
```

Steps 5 and 6 are hard gates. If step 5 clamps, `warnings[]` must say so in user-safe language.
If step 6 produces a blocking gate, **no plan is emitted** — the API returns the gate, and the app
shows a clinician-referral screen. A partial plan is worse than no plan.

## 3. Energy

**BMR — Mifflin-St Jeor**
```
male:   10·W + 6.25·H − 5·A + 5
female: 10·W + 6.25·H − 5·A − 161
intersex/undisclosed: mean of both, and set warnings.estimate_precision = "reduced"
```
W = kg, H = cm, A = years. Use current weight, not goal weight.

*Note (doc 00 §1): Indian body composition tends to yield a lower measured BMR than Mifflin predicts.
We do not apply a correction factor — the evidence for a single population coefficient isn't strong
enough — but this is why the deficit ceiling in §4 is conservative.*

**TDEE = BMR × activity multiplier**

| Level | Multiplier | Description shown to user |
|---|---|---|
| sedentary | 1.200 | Desk job, little deliberate movement |
| light | 1.375 | Light activity or exercise 1–3 days/week |
| moderate | 1.550 | Exercise 3–5 days/week |
| heavy | 1.725 | Hard exercise 6–7 days/week or physical job |

Do **not** add a fifth "athlete 1.9" tier. Self-reported activity is already the largest error term in
the whole calculation; more tiers just move the error around. If step data is available and
consistently contradicts the declared level by more than one tier for 14 days, surface a prompt to
the user — never silently re-tier them.

**Goal adjustment**
| Goal | Adjustment | Ceiling |
|---|---|---|
| fat_loss | −20 % of TDEE | absolute deficit ≤ 750 kcal/day |
| muscle_gain | +12 % of TDEE | absolute surplus ≤ 400 kcal/day |
| maintenance | 0 % | — |

Then §4 clamps.

## 4. Safety clamps (mirror of doc 05 §2 — engine must implement both)

```
target = max(target, floor_kcal[sex])          floor: male 1500, female 1200
target = max(target, BMR × 1.00)               never plan below BMR
if goal == fat_loss and BMI < 22:  target = TDEE          (no deficit)
if BMI < 18.5:                     goal := maintenance, gate: underweight_review
if age >= 65:                      max deficit 15 %
if condition ∩ {type2_diabetes, hypertension, hypothyroid}: max deficit 15 %
if condition ∩ {pregnancy, lactation, post_surgery, ckd, hyperthyroid}: BLOCKING GATE
weekly loss target must fall in 0.25 %–1.0 % of body weight; if the deficit implies more, reduce it
```

## 5. Macros

**Protein — on adjusted body weight, not actual.** This is the correction your current build is
missing and it matters most for exactly your target user (BMI 30+).

```
IBW  = 23.0 × (H/100)²                     [Indian/Asian BMI reference, not 25]
ABW  = W > IBW ? IBW + 0.25 × (W − IBW) : W
protein_g = clamp(rate × ABW, min_g, max_g)
```

| Goal | Rate (g/kg ABW) | Notes |
|---|---|---|
| fat_loss | 1.8 | range 1.5–2.0 available to coach override |
| muscle_gain | 1.8 | range 1.6–2.2; uses actual weight when W ≤ IBW |
| maintenance | 1.1 | range 1.0–1.2 |

Hard caps: `protein_g ≤ 2.2 × ABW` and `≤ 40 % of target kcal`. If `ckd` declared or eGFR unknown in
a user > 60 with diabetes + hypertension → cap at 1.0 g/kg and attach the clinician-referral warning.
Floor: `≥ 0.83 × W` (ICMR RDA) in all cases, so the engine never plans below the national RDA.

**Fat**
```
fat_kcal = fat_pct × target        default 25 %
fat_pct: pcos → 30 %, type2_diabetes → 30 %, muscle_gain → 22 %
minimum: fat_g ≥ 0.6 × ABW  and  fat_pct ≥ 20 %
saturated fat ≤ 10 % of target kcal (≤ 7 % if hypertension or dyslipidemia declared)
```

**Carbs = remainder.** Floor `carb_g ≥ 100`. If the remainder falls below the floor, reduce protein
first (toward its own floor), then raise the target — never breach the carb floor. The engine must
never emit a ketogenic plan by accident.

**Fibre:** 14 g per 1,000 kcal, min 25 g, max 45 g.
**Sodium:** ≤ 2,000 mg default; ≤ 1,500 mg if hypertension.
**Added sugar:** ≤ 5 % of kcal default; ≤ 25 g absolute if type2_diabetes/prediabetes/pcos.
**Water:** 33 ml/kg body weight, min 2.0 L, max 4.0 L. (Your current app hardcodes 3 L for everyone.)

## 6. Medical overrides — applied in this order

Order matters because later rules must be able to tighten, never loosen, earlier ones. Implement as a
declarative table in the rule pack, evaluated in sequence, each producing constraints that are
intersected.

| Priority | Condition | Constraints applied |
|---|---|---|
| 1 | `ckd` | **BLOCKING GATE** — no plan. Referral only. |
| 2 | `pregnancy` \| `lactation` | **BLOCKING GATE** |
| 3 | `post_surgery` | **BLOCKING GATE** unless a coach with clinician attestation unlocks; then `easy_digest` only, no deficit |
| 4 | `hyperthyroid` | **BLOCKING GATE** (unstable energy needs) |
| 5 | `type2_diabetes` \| `prediabetes` | ≥70 % of carb grams from `gi:low`; no `gi:high` items; added sugar ≤25 g; carbs evenly split across ≥4 eating occasions, each ≤55 g; exclude fruit juice, sweets, refined flour; max deficit 15 % |
| 6 | `hypertension` | sodium ≤1,500 mg; exclude `group:prepared` items >400 mg Na/serving; exclude pickles, papad, processed meat, instant noodles; saturated fat ≤7 %; prefer `attr:low_sodium`, potassium-rich veg |
| 7 | `pcos` | added sugar ≤25 g; carb ≤45 % E; protein ≥1.8 g/kg ABW; ≥70 % low-GI carbs; prefer `attr:high_fibre`; fat 30 % E |
| 8 | `hypothyroid` | max deficit 15 %; iodine-adequate; separate soy and calcium-rich items ≥4 h from the morning medication slot; adequate selenium/zinc |
| 9 | allergies | hard exclude by allergen tag, **including cross-contamination tags on prepared items** |
| 10 | `food_preference` | hard exclude by `pref:*` (jain additionally excludes `attr:root_veg`) |
| 11 | `budget_tier` | soft filter: low → 80 % of items must be `cost:low`; premium → no constraint |
| 12 | `lifestyle` | night_shift → shift meal windows, main meal at shift start; office → ≥2 meals must be `attr:portable`; student → prep time ≤15 min |

**Conflict resolution:** if intersecting constraints empty the candidate pool for a meal slot, relax
in this fixed order — budget → lifestyle → region → prep — and never relax allergy, preference, or
condition constraints. If the pool is still empty, emit gate `insufficient_food_coverage` and alert
ops. That alert is your food-DB gap detector; it is more valuable than any dashboard.

## 7. Meal structuring

| meal_count | Distribution |
|---|---|
| 3 | Breakfast 30 %, Lunch 40 %, Dinner 30 % |
| 4 | Breakfast 25 %, Lunch 35 %, Snack 15 %, Dinner 25 % |
| 5–6 | Breakfast 22 %, Mid-morning 8 %, Lunch 30 %, Evening 10 %, Dinner 25 %, (Optional bedtime 5 %) |

Tolerance ±5 percentage points per meal after fill. Rules:
- Every meal ≥ 20 g protein (or ≥ 0.25 g/kg ABW, whichever is greater) — except snacks < 10 % of
  target, which need ≥ 10 g.
- Muscle gain: protein spread as evenly as possible; no meal > 40 % of daily protein.
- Diabetes: carbs per eating occasion ≤ 55 g.
- Night shift: windows shift by the declared shift start; the "breakfast" slot is renamed, not moved.

**Fill algorithm:** greedy by protein density within the candidate pool, then a repair pass that
adjusts quantities (in household-measure increments, not arbitrary grams — 1.5 katori is real,
137 g is not) until the meal is within tolerance. Cap iterations at 50; fall back to the closest
solution and record the residual in the trace.

## 8. Rounding and validation

Round once, at output: kcal → integer, macros → integer grams, quantities → nearest household
increment (0.5 katori, 0.5 roti, 1 tsp, 50 ml).
Then assert:
```
|Σ meal_kcal − target| ≤ 3 %
|Σ protein − protein_target| ≤ 5 g
Σ sodium ≤ sodium_cap
every constraint from §6 still satisfied
```
Failing an assertion is a bug, not a warning. Fail loudly in dev, emit `plan_generation_failed` and
serve the previous plan in prod.

## 9. Explainability trace

Every plan stores an ordered trace. This is what lets a coach defend the plan and lets you debug
three months later:
```json
[{"step":"bmr","formula":"mifflin_st_jeor","inputs":{"w":95,"h":173,"a":29,"sex":"male"},"result":1891},
 {"step":"tdee","multiplier":1.55,"result":2931},
 {"step":"goal_adjust","goal":"fat_loss","pct":-20,"result":2345},
 {"step":"safety_clamp","applied":false,"floor":1500,"bmr_floor":1891},
 {"step":"protein","basis":"abw","ibw":68.8,"abw":75.4,"rate":1.8,"result":136},
 {"step":"override","rule":"none"},
 {"step":"distribute","pattern":"4_meal","split":[25,35,15,25]}]
```

## 10. Dynamic weekly adjustment (v1.1, not v1)

Only run with ≥ 14 days of data and ≥ 5 weight entries in the window. Use the 7-day moving average,
never raw weights.
```
expected = target_rate  (default 0.5 %/week of body weight for fat_loss)
actual   = (MA7_now − MA7_7d_ago) / weight
if adherence < 60 %:            do not change calories. Simplify the plan instead.
if actual < 0.5 × expected:     target −5 % (max 3 consecutive reductions, then gate to coach)
if actual > 1.5 × expected:     target +5 %
if any clamp from §4 binds:     no reduction, ever
```
Hard rule: **cumulative reductions may never take the target below the §4 floors, and the engine may
never reduce a target more than 3 times without human review.** A loop that keeps cutting calories
because a user isn't losing weight is the single most harmful thing this system could do.

## 11. Photo meal detection (v1.2, scoped)

Never auto-log. Pipeline: image → vendor API → map candidates to internal `food_id` via a synonym
table → present top 5 → user confirms dish + portion → log with
`source: photo, confidence: n, was_corrected: bool`. Store the correction pairs; they are your only
path to an Indian-food model later. Vendor is swappable behind `FoodVisionProvider` — do not let
vendor response shapes leak past the adapter.
