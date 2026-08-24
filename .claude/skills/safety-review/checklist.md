# Safety & privacy review checklist

## Clinical floors (docs/05 §2)
- [ ] `target >= 1500` (male) / `1200` (female) and `>= BMR × 1.00` on every code path
- [ ] Deficit <= 750 kcal and <= 20 % of TDEE (<= 15 % for age >= 65, T2D, HTN, hypothyroid)
- [ ] No deficit when BMI < 22; goal coerced to maintenance when BMI < 18.5
- [ ] Carbs >= 100 g; fat >= 20 % E and >= 0.6 g/kg ABW
- [ ] Protein >= 0.83 g/kg actual weight, <= 2.2 g/kg ABW, <= 40 % E
- [ ] Coach override re-validated server-side against the same floors
- [ ] Auto-adjuster: adherence gate, 3-reduction freeze, no reduction that breaches a floor

## Gates (docs/05 §3)
- [ ] CKD, pregnancy, lactation, hyperthyroid, T1D/insulin, ED history, BMI < 16 → no plan emitted
- [ ] Age < 18 rejected at the API boundary, before any health field is persisted
- [ ] Gate returns `PLAN_GATE_BLOCKED` with the referral copy, never a partial plan

## Copy (docs/05 §7)
- [ ] User-facing strings come from the server-side copy table, verbatim
- [ ] No "treat", "cure", "manage", "reverse", "control" beside a condition name
- [ ] No judgemental status labels ("Obese"), no "Missed" markers, no failure-framed notifications
- [ ] Disclaimer present on every plan surface and every export

## Privacy (docs/13)
- [ ] No name, phone, email, weight, BMI or condition in any log line or exception
- [ ] No health data in a URL path or query string
- [ ] Health-field read has a grant check AND an expiry check AND an audit row
- [ ] Condition-based notification targeting only when `content_class = 'clinical'`
- [ ] New health column added to the retention table and to an RLS policy
- [ ] Export and deletion paths cover the new field

## Money (docs/11, docs/12)
- [ ] Integer paise; no float arithmetic on money
- [ ] Ledger append-only; reversals as offsetting entries
- [ ] Idempotency on every money-creating POST; webhook replays are no-ops
- [ ] Commission computed on net, not gross
