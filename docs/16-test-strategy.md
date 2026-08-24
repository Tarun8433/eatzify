# 16 — Test Strategy & Golden Vectors

## 1. Pyramid and coverage floors

| Layer | Tool | Floor | Notes |
|---|---|---|---|
| Engine unit + golden vectors | Jest/Vitest | **95 %** | Pure functions; no excuse for gaps |
| Billing & commission math | Jest | **90 %** | Money bugs are unrecoverable |
| API contract | supertest + Pact-style snapshots | 80 % of endpoints | Error envelope asserted |
| RBAC matrix | integration | **100 % of doc 10 rows** | One test per cell. This is compliance evidence. |
| Repository/DB | Testcontainers Postgres | 70 % | Real Postgres, real constraints |
| Flutter unit/controller | flutter_test | 60 % | |
| Flutter widget | flutter_test | Every screen: loading/error/empty | |
| E2E | Patrol or integration_test | 8 critical journeys | |

## 2. Golden vectors — copy these into `engine.golden.spec.ts` verbatim

All computed with rule pack v1.0.0: Mifflin-St Jeor · activity multipliers per doc 04 §3 ·
fat_loss −20 % · protein on ABW (IBW at BMI 23, ABW = IBW + 0.25(W−IBW)) · fat 25 % default.

### GV-01 — baseline male fat loss (the profile from your screenshots)
```
in:  male, 29y, 173 cm, 95.0 kg, moderate, fat_loss, veg, 4 meals, conditions: none
out: bmr 1891 · tdee 2931 · target 2345 · ibw 68.8 · abw 75.4
     protein 136 g (23 % E) · fat 65 g (25 % E) · carbs 304 g (52 % E)
     clamps: none · gates: none
     meals: 586 / 821 / 352 / 586 kcal (±5 pp), each ≥20 g protein
```
*Regression guard: the current build outputs 2,431 kcal / P122 / C334 / F68 for this exact input.
This test must fail against the current engine. That is the point.*

### GV-02 — female, PCOS
```
in:  female, 28y, 160 cm, 68.0 kg, light, fat_loss, conditions: [pcos]
out: bmr 1379 · tdee 1896 · target 1517 · abw 61.2
     protein 110 g · fat 51 g (30 % E, pcos override) · carbs 155 g (41 % E ✓ ≤45 %)
     constraints: added_sugar ≤25 g · ≥70 % low-GI carbs · fibre ≥25 g
     clamps: none (1517 > 1379 BMR floor, > 1200 female floor)
```

### GV-03 — male muscle gain, below IBW (protein on actual weight)
```
in:  male, 32y, 178 cm, 62.0 kg, moderate, muscle_gain
out: bmr 1578 · tdee 2445 · target 2739 (+12 %, surplus 294 ≤ 400 cap)
     ibw 72.9 → W < IBW so basis = actual weight 62.0
     protein 112 g (16 % E) · fat 76 g (22 % E, gain override) · carbs 402 g
```

### GV-04 — older male, T2D on oral meds
```
in:  male, 60y, 170 cm, 88.0 kg, sedentary, fat_loss, conditions: [type2_diabetes]
out: bmr 1648 · tdee 1977 · target 1680 (deficit capped at 15 %, not 20 %)
     abw 71.9 · protein 101 g (1.4 g/kg, reduced for age+condition) · fat 56 g (30 % E) · carbs 193 g
     constraints: ≥70 % low-GI · no gi:high items · carbs ≤55 g per occasion · added sugar ≤25 g
     warnings: [renal_protein_caution]  gates: none
```

### GV-05 — underweight female requesting fat loss (clamp path)
```
in:  female, 35y, 155 cm, 46.0 kg, light, fat_loss
     bmi 19.1 → below 22 → NO DEFICIT
out: target = tdee = 1503 · goal coerced to maintenance
     protein 51 g (1.1 g/kg) · fat 42 g · carbs 231 g
     warnings: [deficit_suppressed_low_bmi]
```

### GV-06 — hard floor engaged
```
in:  female, 45y, 148 cm, 44.0 kg, sedentary, fat_loss
     bmr 1071 · tdee 1285 · raw target 1028
out: target 1200 (female absolute floor) — but also bmi 20.1 < 22 → no deficit → target 1285
     order matters: BMI check precedes the floor. Assert target == 1285, not 1200.
```

### GV-07 — blocking gates (assert NO plan is emitted)
```
[pregnancy] → gate pregnancy, plan null
[lactation] → gate lactation, plan null
[ckd]       → gate ckd, plan null
[post_surgery] no attestation → gate post_surgery_needs_clinician, plan null
[hyperthyroid] → gate hyperthyroid, plan null
age 17y11m   → AGE_INELIGIBLE at the API boundary, no engine call at all
bmi 15.8     → gate bmi_critical, plan null
```

### GV-08 — determinism
Run GV-01 1,000 times. Assert byte-identical JSON output including meal item order and quantities.
Then run with a different `user_id` and assert the food *selection* differs while the *targets* are
identical. This proves the seeded PRNG is wired to the right thing.

### GV-09 — rule pack isolation
Generate GV-01 under v1.0.0, then activate v1.1.0 with `fat_pct: 0.30`, regenerate, and assert the
v1.0.0 plan is unchanged when re-read (snapshot integrity) while the new plan reflects the new pack.

### GV-10 — food DB constraint
```
insert food: kcal 34, P4, C5, F1  → derived 45 kcal, 32 % deviation → REJECTED (atwater_consistent)
insert food: kcal 134, P12, C8, F3 → derived 107 kcal, 25 % deviation → REJECTED
insert food: kcal 130, P2.7, C28, F0.3 (cooked rice) → derived 125.5, 3.5 % → ACCEPTED
```

### GV-11 — adjuster safety (v1.1)
```
14 days data, adherence 45 % → assert NO calorie change (adherence gate)
adherence 80 %, actual loss 0.1 %/wk vs expected 0.5 % → target −5 %
same again ×3 → 3rd reduction sets adjuster_frozen = true and emits human_review_required
4th attempt → assert no change, regardless of input
any reduction that would breach a §4 floor → assert no change
```

### GV-12 — weight entry plausibility
```
existing weight 95.0 on day D; new entry 65.0 on day D+1
→ delta 30 kg in 1 day → is_suspect true → excluded from MA7 and from the adjuster
→ "Change" readout computed from MA7, never from min/max. Assert change ≠ −30.0.
```

## 3. Critical E2E journeys

1. Signup → onboarding (no conditions) → plan generated → log breakfast from plan → home rings update.
2. Onboarding declaring pregnancy → gate screen → no plan → no health row beyond what consent covered.
3. Free user hits regeneration limit → upgrade sheet → Play purchase (test track) → entitlement
   refreshes → regeneration succeeds.
4. Coach invites client → client accepts with `progress` scope only → coach sees weight, **cannot** see
   conditions → client revokes → coach screen shows access-ended state within 60 s.
5. Partner referral link → signup → BASIC purchase → commission accrues → refund → commission reverses.
6. Subscription T-7 → T-3 → expiry notifications → downgrade to FREE → data still present → repurchase
   restores access.
7. Offline: log three foods with no network → reconnect → all three sync exactly once (idempotency).
8. Coach attempts to override a plan below the calorie floor → API rejects with the floor violation →
   UI explains why.

## 4. Test data

Synthetic generator producing 500 profiles spanning: every condition combination the engine accepts,
BMI 16–45, ages 18–80, all activity levels, all preferences. Run the whole set through the engine
nightly in CI and assert:
- zero unhandled exceptions,
- zero outputs below any §2 floor,
- zero gate bypasses,
- `insufficient_food_coverage` rate < 2 % (this is your food-DB coverage metric).

Never use production data in tests. Never commit a real phone number to a fixture.

## 5. Manual QA checklist per release

Device matrix: one low-end Android (2 GB RAM, Android 11), one mid (Android 14), one iOS (when
shipped). Plus: 200 % font scale · dark mode · airplane mode · slow 3G (throttled) · Hindi locale ·
Health Connect permission denied · Health Connect not installed · time zone changed mid-session ·
device date set to 00:30 IST (diary-day boundary).
