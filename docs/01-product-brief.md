# 01 — Product Brief

## 1. One sentence

Eatzify generates and maintains practical Indian diet plans, and gives fitness coaches the software
to run their clients on those plans.

## 2. The problem, stated honestly

Two different problems are tangled in your current spec.

**Problem A (consumer):** an Indian adult who wants to lose fat gets either a generic Western
calorie app that doesn't know what a katori of dal is, or a ₹500 PDF from an Instagram coach that
ignores their diabetes. They abandon both inside three weeks.

**Problem B (coach):** an independent Indian fitness coach with 20–60 clients runs their entire
business on WhatsApp and Excel. They lose clients to poor follow-up, not poor programming. They have
no software and cannot build any.

These need different products. Problem A is a hard, crowded, low-ARPU consumer market. Problem B is
a smaller, easier, higher-ARPU, referral-driven market where the customer brings their own users.

## 3. Recommendation

**Lead with Problem B. Ship Problem A as the client-facing surface of it.**

Rationale: it matches your business preference for systemised, delegable, referral-compounding
models; the coach is the distribution channel *and* the payer; it lets you launch with a modest food
database because a coach can override anything the engine gets wrong; and it defers the hardest
consumer problems (retention, CAC, photo logging accuracy) until you have revenue.

It also fixes an incoherence in the current plan: you have both a ₹22,999 coaching plan (you employ
the coach) and a 40 % partner commission (the coach employs you). Those are opposite businesses. Pick
the second. You are a platform, not a coaching agency. Doc 19 Q1.

## 4. Positioning statement

> For independent Indian fitness coaches and small gyms who run their clients on WhatsApp,
> Eatzify is client-management software with an Indian diet engine built in — it produces the plan,
> tracks compliance, and flags who is slipping, so the coach can handle 3× the clients without
> hiring. Unlike generic consumer calorie apps, every plan is built from Indian foods and household
> measures and can be overridden by the coach in one tap.

## 5. What Eatzify is not

- **Not a medical product.** It does not diagnose, treat, cure or manage disease. It does not replace
  a doctor or a registered dietitian. This is a design constraint, not just a disclaimer — see doc 05.
- **Not for under-18s.** Onboarding blocks them.
- **Not a supplement store.** No supplement recommendations or sales in v1.
- **Not a "fastest weight loss" product.** No copy, badge, or challenge that rewards rapid loss.
- **Not an aggressive-notification product.** Streaks and reminders yes; shame mechanics no.

## 6. Success metrics (first 12 months)

**Primary:** number of coaches with ≥5 active paying clients at month end. This single number
captures the whole thesis.

Supporting:
| Metric | Target | Why |
|---|---|---|
| Coach 90-day retention | > 60 % | If coaches churn, nothing else matters |
| Client D30 logging retention | > 35 % | Compliance is the coach's product |
| Plans generated per coach per month | > 8 | Engine is actually being used |
| Plan override rate | 20–40 % | Below 20 % = coaches aren't engaged; above 40 % = engine is wrong |
| Support tickets per 100 MAU | < 4 | |
| Gross margin per coaching client | > 55 % | See doc 12 |

**Anti-metrics — track these and act if they rise:** average daily deficit; share of users whose
target is at the hard floor; share of users with goal weight below BMI 18.5; 7-day log-then-vanish rate.
A calorie app that quietly optimises engagement over wellbeing is a liability.

## 7. Brand and naming

Fix before launch: your screens say **Eatzify**, the coach dashboard shares
`https://fitfuel.app/coach/prashant`, and the footer says **© 2024** while in-app dates read 2026.
One name, one domain, one copyright year, everywhere. Doc 15 D-01.
