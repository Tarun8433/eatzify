# Eatzify — Pre-Development Documentation Set

**Owner:** Tarun (Zynthovo Digital Pvt Ltd)
**Status:** Pre-build. Nothing in here is code. Everything in here is a decision, a constraint, or a contract.
**Last updated:** 2026-08-24

---

## Why this set exists

You already have a working prototype (20 screens shipped) and a very large feature wishlist. That is
the most dangerous stage of a product: enough exists that new work feels cheap, but no written
contract exists, so every new feature quietly contradicts an old one. Four different bottom
navigation bars across your screenshots is that contradiction made visible.

These documents exist so that (a) you can hand any single task to Claude Code and get output that
fits the system, and (b) six months from now the diet engine still behaves the way you decided
today, not the way whoever touched it last felt like.

## Read order

| # | File | Read when |
|---|------|-----------|
| — | `CLAUDE.md` | Before every Claude Code session. This is the agent's operating manual. |
| 00 | `docs/00-research-findings.md` | First. Five findings here change your architecture and your pricing. |
| 01 | `docs/01-product-brief.md` | Positioning, who it's for, what it is not. |
| 02 | `docs/02-prd.md` | Scope, personas, MVP cut line, acceptance criteria. |
| 03 | `docs/03-domain-model.md` | Vocabulary. Every ambiguous word in your spec gets one meaning here. |
| 04 | `docs/04-diet-engine-spec.md` | The algorithm, as a deterministic, versioned, testable spec. |
| 05 | `docs/05-clinical-safety-guardrails.md` | Non-negotiable. Read before touching the engine. |
| 06 | `docs/06-architecture.md` | Services, boundaries, deployment topology. |
| 07 | `docs/07-adr-log.md` | Why each major technical choice was made, and what would reverse it. |
| 08 | `docs/08-data-model.md` | Postgres DDL, constraints, retention. |
| 09 | `docs/09-api-spec.md` | REST contract, error envelope, idempotency. |
| 10 | `docs/10-rbac-access-matrix.md` | Who can see which field. The coach-data question, answered. |
| 11 | `docs/11-subscriptions-billing.md` | Plan matrix, store fees, proration, renewal, RBI limits. |
| 12 | `docs/12-partner-commission.md` | Attribution, commission math, payouts, and the margin problem. |
| 13 | `docs/13-privacy-dpdp.md` | DPDP Act obligations, consent design, retention. |
| 14 | `docs/14-flutter-app-spec.md` | App shell, navigation IA, folder structure, offline rules. |
| 15 | `docs/15-ux-audit-screenshots.md` | 31 defects found in the current build, prioritised. |
| 16 | `docs/16-test-strategy.md` | Golden vectors for the engine. Copy these into unit tests verbatim. |
| 17 | `docs/17-roadmap-backlog.md` | Epics, sequencing, MVP cut, estimates. |
| 18 | `docs/18-ops-runbook.md` | Envs, CI/CD, backups, observability, incident response. |
| 19 | `docs/19-open-questions.md` | 18 decisions only you can make. Blocking items marked. |
| 20 | `docs/20-foundations-boilerplates.md` | Before writing code. What to adopt, what to build, licence traps, pinned package manifests. |

Supporting: `prompts/claude-task-templates.md`, `PLACEMENT.md` (repo layout), `product-operating-manual.md`

The backend `.env.example` moved to `_backend-claude-config/` — it belongs in the API repo, not here.

## How to use this with Claude Code

1. Put this whole folder at the repo root. Keep `CLAUDE.md` at the root, not inside `docs/`.
2. Start every session by naming the doc that governs the task:
   *"Implement POST /v1/plans per docs/09-api-spec.md §4.2, using the engine spec in
   docs/04-diet-engine-spec.md. Do not deviate from the rule pack constants."*
3. When Claude proposes something these docs forbid, the doc wins — or you update the doc first.
   Never let the code and the doc disagree silently.
4. Every engine change requires the golden vectors in `docs/16-test-strategy.md` to be re-run and
   the rule pack version bumped. No exceptions.

## The five things that will most change your plan

1. **Google Fit dies at the end of 2026.** Your step tracking uses it. Migrate to Health Connect now.
2. **DPDP Act substantive obligations bite on 13 May 2027.** Your coach-sees-client-health-data model
   is the single biggest exposure in the product. It needs consent architecture, not a permission flag.
3. **Coaching plans above ₹15,000 cannot silently auto-renew** under the RBI E-mandate Framework 2026.
4. **Your commission rates (30–40%) plus store fee plus GST leave ~₹687/month to pay a human coach**
   on a 12-month coaching plan. The math is in doc 12. It does not close.
5. **The prototype's own macro output contradicts your written spec** (122 g protein where the spec
   demands 136–190 g). The engine is not implementing the rules you wrote. Doc 16 proves it.
