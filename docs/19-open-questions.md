# 19 — Open Questions

Decisions only you can make. **[BLOCKING]** items stop Phase 1 work in that area.

## Business model

**Q1 [BLOCKING]** — Coach-first (B2B2C) or consumer-first? Doc 01 recommends coach-first, ADR-008
follows from it, and the entitlement model, pricing and roadmap all change if you choose otherwise.
Answer this before E5/E6/E7 start.

**Q2 [BLOCKING]** — Do you sell coaching first-party at all? If yes, you need coach payroll or
contracts, a capacity model, SLAs, and an answer to the ₹687/month margin problem in doc 12 §1.

**Q3** — Is Eatzify a Zynthovo product with a shared identity, or a standalone brand? Affects the Play
listing, the developer account, the privacy policy entity, and the GST invoicing entity.

**Q4** — Who is the named Grievance Officer under DPDP? A real person with a real published contact.

**Q5** — Do you have access to a qualified nutritionist or dietitian to review the rule pack? Doc 05
§8 requires one before the first rule pack is activated. If not, that is a hiring/contracting task on
the critical path, not a nice-to-have.

## Pricing

**Q6** — Add a monthly plan (₹249 BASIC / ₹549 PRO)? Doc 11 §2 argues yes: a ₹699 minimum first
purchase is a hard barrier and you have no trial-conversion landing spot without it.

**Q7 [BLOCKING for E5]** — For any product above ₹15,000/year, do you bill monthly, quarterly, or use
assisted AFA renewal? The RBI framework forces a choice (doc 00 §6). This changes the renewal job,
the checkout UX, and the entitlement expiry logic.

**Q8** — Play billing only, or web checkout too? Web is worth ~₹650 per PRO 12M sale but needs care
with Play's anti-steering policy. Decide before you build the checkout abstraction, not after.

**Q9** — Commission rates: are you comfortable with 25 %/30 % first purchase and 10 %/12 % renewals
capped at 12 months (doc 12 §2)? Your original 20–40 % with perpetual recurring does not survive the
unit economics.

## Product scope

**Q10** — What is the *actual* minimum food database size you'll launch with? Doc 17 assumes 600
published items. Below ~400 with good household measures, plans will repeat and users will notice.

**Q11** — Which regional cuisines do you cover at launch? North Indian only is a legitimate v1 choice
and much cheaper than pan-India. Pick explicitly rather than by accident of whatever INDB contains.

**Q12** — Do you support Jain and vegan preferences at launch? Both need food-tagging work (Jain
excludes root vegetables, which is a tag you must apply per item).

**Q13** — Hindi UI at launch or Phase 2? Doc 17 says Phase 2, scaffolding at launch. Confirm — if your
first partner cohort's clients are Hindi-first, this moves up.

**Q14** — Is the admin panel Flutter web (ADR-006) or React? You're currently learning React/TypeScript;
using this project to learn it is defensible but adds schedule risk to E8.

## Compliance & risk

**Q15 [BLOCKING]** — Legal review of: terms of service, privacy policy, the partner agreement, and
the "Verified Partner" claim (doc 00 §8, doc 12 §6). Budget ₹40–80k. Do not launch without it.

**Q16 [BLOCKING for E2]** — Confirm the reuse terms for INDB and for the IFCT 2017 tables for a
commercial product. The convenient npm packages are AGPL-3.0 and must not be linked (ADR-012).

**Q17** — CA confirmation on: TDS section and current rate on partner commissions, GST treatment of
commissions (forward vs reverse charge), and GST on your subscription revenue (SaaS/OIDAR
classification). Doc 12 §5 has placeholders where these numbers go.

**Q18** — Do you want an internal "coach can attest a clinician's guidance" mechanism (doc 05 §3
clinician gate)? It unlocks post-surgery and insulin-using users, which is real revenue, but it makes
you dependent on the honesty of a coach's attestation. My recommendation: don't build it in v1. Block
those conditions cleanly and revisit when you have a clinical adviser on the team.

---

## My recommendations, if you want a default

1. Coach-first. No first-party coaching. Platform fee per active client seat.
2. Add monthly plans. Bill anything above ₹15,000 in monthly instalments.
3. Launch Android-only, English UI with Hindi scaffolding, North + common pan-India foods, ~600 items.
4. 25 %/30 % commissions, renewals capped at 12 months.
5. Hard-block every condition in doc 05 §3's BLOCK list. No clinician-attestation mechanism in v1.
6. Spend the legal and CA money before launch, not after the first dispute.
7. Close Phase 0 before writing a single new feature. The engine currently disagrees with your own
   spec, and everything else you build on top of it inherits that.
