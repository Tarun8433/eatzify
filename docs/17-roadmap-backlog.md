# 17 — Roadmap & Backlog

Estimates assume one developer (you) at ~25 focused hours/week. They are *ranges* because the food
database and the compliance work have irreducible uncertainty.

## Phase 0 — Stop the bleeding (2–3 weeks)

Fix what is wrong in the current build before adding anything. Nothing new ships until this closes.

| # | Task | Est |
|---|---|---|
| 0.1 | Rewrite the engine against doc 04; land golden vectors GV-01…GV-12 | 5–7 d |
| 0.2 | Safety layer: floors, gates, approved copy, disclaimer on every plan surface | 3–4 d |
| 0.3 | Remove "Obese" chip, red "Missed" markers, shame copy | 1 d |
| 0.4 | One navigation shell; delete the hamburger menu and three redundant tab bars | 3–4 d |
| 0.5 | Food table constraints + review workflow; purge the two invalid rows | 2 d |
| 0.6 | Weight entry: one per diary day, plausibility confirm, MA7 display, fix the −30 kg bug | 2 d |
| 0.7 | Mask PII in admin; remove the unrestricted CSV export | 1–2 d |
| 0.8 | Single brand: kill the fitfuel.app reference; build-time version and year | 0.5 d |
| 0.9 | `is_demo` flag + metrics exclude it + no seeders in prod | 1 d |

## Phase 1 — MVP (8–10 weeks)

| Epic | Tasks | Est |
|---|---|---|
| **E1 Identity & onboarding** | OTP auth, profile, health profile versioning, screening, consent screens, age gate at DB level | 8–10 d |
| **E2 Food database** | INDB/IFCT import pipeline, ~600 published foods, household measures, synonyms, recipes with derived nutrition, search index | 10–14 d ⚠ *biggest single unknown* |
| **E3 Engine + plans** | rule pack loader, plan persistence, revisions, alternates, coach override with server-side floor re-validation | 8–10 d |
| **E4 Logging & progress** | food/water/weight logs, diary-day logic, Health Connect steps, MA7 trend, adherence | 8–10 d |
| **E5 Billing** | catalogue, entitlements, Play Billing 9.x, Razorpay web, trial, proration, renewal jobs, `requires_afa` handling | 10–12 d |
| **E6 Coach surface** | assignments, consent grants, client list/detail, check-in queue, alerts, chat | 10–12 d |
| **E7 Partner** | referral codes, attribution, commission ledger, payouts, dashboard | 8–10 d |
| **E8 Admin** | consolidated user screen, food CRUD + import, coach verification, tickets, notifications with content_class, audit viewer | 10–12 d |
| **E9 Compliance** | consent ledger, privacy screen, export/delete, retention jobs, breach playbook, policies published | 6–8 d |
| **E10 Hardening** | RBAC matrix tests, rate limits, monitoring, backups, restore drill, Play listing + data safety form | 6–8 d |

**MVP definition:** a coach can onboard a client, the client gets a safe and correct plan, logs
against it, the coach sees compliance, and money moves correctly to both you and the partner.

## Phase 2 — Retention (6–8 weeks, after 20 paying coaches)

- Weekly auto-adjustment (doc 04 §10) with the safety freeze
- Weekly client feedback loop feeding plan regeneration
- PDF export with proper Indian typography
- Hindi UI (the translation, not just the scaffolding)
- Reminder engine with custom times and quiet hours
- Milestones and non-weight streaks (logging streaks, protein-target streaks — never weight streaks)
- Coach templates: save a plan as a reusable template

## Phase 3 — Differentiation (gated on evidence)

| Feature | Ship only when |
|---|---|
| Photo meal detection | Food DB > 2,000 items with synonyms, and you've measured that search-based logging is the top abandonment point |
| Behaviour insights | ≥ 60 days of logs for ≥ 200 users |
| Progress projection | You can express it as a range and have a month of backtested accuracy |
| iOS app | Android MAU > 3,000 or a partner demands it |
| Web app for coaches | A coach explicitly asks twice — coaches work from phones |
| Transformation programmes | You have 3 partners who will co-sell one |
| Community/groups | You have moderation capacity. This is a support cost, not a feature. |
| Workout plans | Never, in-house. Partner or integrate. It doubles your safety surface for no margin. |

## Explicitly deferred, with reasons

| Item | Why not now |
|---|---|
| First-party COACHING tier | ADR-008: margin doesn't close, competes with partners |
| Supplement recommendations/sales | Doc 00 §1: DGI 2024 explicitly discourages; reputational risk |
| AI chat coach | Cost per session at your ARPU, plus it will give medical advice you can't control |
| Leaderboards on weight | Doc 05 §6 |
| Multi-language beyond hi | Cost per language is real; prove hi first |
| Gamification with streak-breaking penalties | Doc 05 §6 |

## Milestones

| Milestone | Definition of success |
|---|---|
| M1 (week 3) | Phase 0 closed; golden vectors green; one nav shell |
| M2 (week 8) | Engine + food DB + logging working end to end for one internal test user |
| M3 (week 12) | Billing live in Play's test track; 3 friendly coaches onboarded free |
| M4 (week 14) | Closed beta: 5 coaches, 40 clients, real money, no P0 for 14 days |
| M5 (week 18) | Public launch, Android, with policies published and the DPDP feature set complete |

## Sequencing advice

Build **E2 (food database) first and in parallel with everything**. It is the only task whose duration
you cannot compress with better code, and every other epic is blocked on it being *good enough*. A
plan built from 600 well-tagged Indian foods with household measures is a product; the same engine
over 60 foods is a demo. This is where the "deep research" work actually pays off.
