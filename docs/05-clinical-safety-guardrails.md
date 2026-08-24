# 05 — Clinical Safety Guardrails

**Status: non-negotiable.** These rules override product, growth, and engineering convenience. If a
feature request conflicts with this document, the feature loses. Changes here require a named
reviewer with a clinical qualification, recorded in the ADR log.

## 1. Why this document exists

You are building software that tells people with diabetes, high blood pressure, thyroid disease and
PCOS how much to eat. It sets calorie deficits automatically and adjusts them weekly without a human
in the loop. Three failure modes follow directly from that design:

1. **Under-eating spiral.** A user doesn't lose weight (water retention, mis-logging, a bad scale),
   the auto-adjuster cuts calories, repeat. Four cycles and you have prescribed a semi-starvation diet
   to someone who trusted an app.
2. **High protein into undiagnosed kidney disease.** Diabetic nephropathy is common and often silent
   in India. A 2 g/kg protein target is genuinely harmful in reduced renal function.
3. **Reinforcing disordered eating.** A calorie app with streaks, "Missed" markers, an "Obese" status
   chip and a rapid-loss badge is an excellent disordered-eating accelerant. Your current build has
   three of those four.

None of these require malice. They are the default behaviour of a naive implementation.

## 2. Hard numeric floors (engine must enforce — doc 04 §4)

| Rule | Value |
|---|---|
| Absolute minimum planned intake, male | 1,500 kcal/day |
| Absolute minimum planned intake, female | 1,200 kcal/day |
| Never plan below BMR | `target ≥ BMR × 1.00` |
| Maximum daily deficit | 750 kcal |
| Maximum deficit as % of TDEE | 20 % (15 % if age ≥ 65, or T2D / HTN / hypothyroid) |
| Maximum planned rate of loss | 1.0 % of body weight per week |
| Minimum planned rate (fat loss) | 0.25 %/week — below this, tell the user maintenance is fine |
| No deficit permitted if | BMI < 22 |
| Goal forced to maintenance if | BMI < 18.5 |
| Minimum carbohydrate | 100 g/day |
| Minimum fat | 20 % of kcal and 0.6 g/kg ABW |
| Minimum protein | 0.83 g/kg actual weight (ICMR RDA) |
| Maximum protein | 2.2 g/kg ABW, and ≤ 40 % of kcal |
| Maximum consecutive auto-reductions | 3, then human review required |

## 3. Condition gates

**BLOCK — the engine does not generate a plan. Referral screen only.**
`ckd` / declared kidney disease · `pregnancy` · `lactation` · `hyperthyroid` ·
`type_1_diabetes` · insulin use of any kind · `eating_disorder` history declared ·
`post_surgery` (unless unlocked, below) · age < 18 · BMI < 16.

**CLINICIAN-GATED — plan only after a coach with a recorded clinician attestation unlocks it, and
the plan carries a visible "reviewed by" attribution:**
`post_surgery` · `type2_diabetes` with insulin · `hypertension` on 3+ medications ·
age ≥ 70 · BMI ≥ 40 · declared cardiac event within 6 months.

**PLAN WITH CONSTRAINTS (doc 04 §6):**
`type2_diabetes` (oral meds/diet-controlled) · `prediabetes` · `hypertension` · `pcos` ·
`hypothyroid` (stable, on medication).

**A note on the gates you will be tempted to remove:** every one of these blocks costs you signups.
Removing them costs you the company. `post_surgery` in your original spec sits in a multi-select
alongside "None" with no gate at all — an app that hands a post-operative patient an algorithmic
calorie deficit is the kind of thing that ends a product.

## 4. Screening at onboarding

Ask three questions, once, plainly, no scoring shown to the user:
1. "Has a doctor ever told you to follow a specific diet, or to avoid a specific nutrient?" → yes
   routes to clinician gate.
2. "Are you currently taking insulin or medication for kidney disease?" → yes routes to block.
3. "In the last year, have you been treated for, or worried about, an eating disorder?" → yes routes
   to a support screen with no plan generated and no re-ask for 90 days.

Store the answers as consented health data with the shortest justifiable retention. Never use them
for segmentation, marketing, or partner-visible fields.

## 5. Red-flag detection during use

| Signal | Action |
|---|---|
| Goal weight implies BMI < 18.5 | Reject at input with plain explanation. No override. |
| Logged intake < 60 % of target for 5 of 7 days | Suppress all streak/badge UI; show a supportive check-in; notify coach if assigned |
| Weight loss > 1.5 %/week for 2 consecutive weeks | Auto-raise target to maintenance, notify coach, require acknowledgement to resume deficit |
| Weight loss > 5 % in 30 days unintentionally | Referral screen |
| 3 auto-reductions reached | Freeze the adjuster, escalate to human |
| User asks the app about fasting limits, purging, or "how little can I eat" | No numeric answer. Support screen. |
| Weight entry delta > 3 kg within 7 days | Confirm dialog; if confirmed, flag for review, don't feed the adjuster |

## 6. Things the product must never do

- Never show a bare judgemental status chip ("Obese", "Overweight") as a headline. Show the number
  with context and a neutral label. Your current profile screen does exactly this.
- Never mark past days red as "Missed". Use a neutral "not logged".
- Never rank users against each other on weight lost, or run a leaderboard on weight.
- Never send a notification implying failure ("You've fallen behind", "You skipped again").
- Never gate a *safety* message behind a paywall. Referral screens, floors and warnings are free-tier.
- Never allow a coach or partner to lower a user's target below the §2 floors. The override UI must
  refuse it and say why.
- Never target push notifications by health condition for commercial content (doc 13 §5).
- Never claim to treat, cure, manage, reverse or control any disease.
- Never present the weekly adjuster's output as a prediction of results.
- Never store or infer a condition the user did not declare.

## 7. Approved copy (use verbatim; do not paraphrase)

**Under-18 block:**
> Eatzify is built for adults, so we can't create a plan for you yet. Nutrition needs during growth
> are different and are best handled with a doctor or a registered dietitian who can see the full
> picture. If you'd like, we can send information you could share with a parent or guardian.

**Blocking condition gate:**
> Based on what you've told us, a plan generated by an app isn't the right tool here — your needs
> depend on clinical details we can't see. Please speak to your doctor or a registered dietitian.
> They may be happy to set targets that we can then help you follow day to day.

**Clinician gate (coach-unlockable):**
> This needs a clinician's input before we set your targets. Your coach can unlock it once they've
> confirmed your doctor's guidance.

**Safety clamp applied:**
> We've set your daily target a little higher than your goal alone would suggest. Going lower than
> this isn't safe or sustainable, and it usually slows results rather than speeding them up.

**Disclaimer (every plan screen, every export, footer of onboarding):**
> Eatzify provides general nutrition and wellness information. It is not medical advice, and it does
> not diagnose or treat any condition. Always consult a qualified healthcare professional about your
> health, especially before changing your diet if you have a medical condition or take medication.

**Eating-disorder support routing:**
> Thanks for telling us. We're not going to set calorie or weight targets for you — that wouldn't be
> safe or kind. Support from a professional who specialises in this makes a real difference, and
> we're happy to help you find it.
> *(Link: National Alliance for Eating Disorders helpline / a local professional directory. Verify
> the India-appropriate resource with a clinician before shipping this string.)*

## 8. Review cadence

- Rule pack changes: reviewed by a qualified nutrition professional before merge. Record who, in
  `docs/07-adr-log.md`.
- Quarterly: pull the distribution of issued targets. Alert on any target within 5 % of a floor,
  any user with 2+ auto-reductions, any condition gate bypassed.
- Annually: re-check against the current ICMR-NIN guidance.

## 9. Liability posture (not legal advice — get a lawyer)

Three things a lawyer will ask for and you should prepare now: (1) terms of service that accurately
describe the product as informational, (2) evidence that safety floors exist and are enforced in code
with tests, (3) an audit trail showing who changed a clinical constant and when. The engine's
determinism and trace are as much a legal asset as an engineering one.
