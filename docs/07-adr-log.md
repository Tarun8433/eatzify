# 07 — Architecture Decision Log

Format: decision · context · consequences · what would reverse it. Add a new ADR rather than editing
an old one. Never delete.

---

### ADR-001 — Rule-based engine, not an LLM, for plan generation
**Status:** accepted (2026-08-24)
**Context:** LLM-generated diet plans are fast to build and impossible to defend. They are
non-deterministic, cannot be unit-tested, silently violate constraints, and cannot produce an
audit trail that stands up when someone asks "why did your app tell my diabetic mother to eat this?"
**Decision:** deterministic rule engine with a versioned rule pack. LLMs may later be used for
*presentation* (rewriting a plan into friendlier language) and for *food matching*, never for
targets or constraints.
**Consequences:** more upfront specification work (doc 04); every plan is reproducible and explainable.
**Reversal trigger:** none foreseeable for target computation.

---

### ADR-002 — Engine is a pure package, not a service
**Decision:** `packages/diet-engine` has no I/O. Inputs in, output out.
**Consequences:** sub-millisecond tests; can run in the app for offline preview; forces the rule pack
abstraction. Cost: the API layer must assemble inputs, which is a little more plumbing.

---

### ADR-003 — Postgres as the single source of truth
**Context:** the domain contains a commission ledger, entitlements, and a consent record. Those want
ACID and foreign keys.
**Decision:** Postgres 16. `jsonb` for plan traces and rule-pack snapshots. No MongoDB.
**Reversal trigger:** none. If food/recipe search outgrows Postgres FTS, add Meilisearch as an index,
not as a source of truth.

---

### ADR-004 — NestJS for the backend
**Context:** candidate stacks were NestJS, FastAPI and ASP.NET Core, all of which the team knows.
**Decision:** NestJS, primarily so `packages/contracts` and `packages/diet-engine` are shared with
the Flutter-adjacent tooling in one language and one type system, and so the engine can eventually
run client-side.
**Consequences:** Node's numeric behaviour requires discipline on money (integer paise) and rounding.
**Reversal trigger:** if the team's TypeScript capacity becomes the constraint, ASP.NET Core is the
fallback — but the engine package would then need a port, which is expensive. Decide now, not later.

---

### ADR-005 — One Flutter app for client and coach, role-gated
**Decision:** single binary, role resolved at login, separate shells inside.
**Consequences:** one release pipeline, one crash dashboard. Risk: coach features bloat the client
APK. Mitigate with deferred components if the APK passes 40 MB.
**Reversal trigger:** coach surface exceeding ~20 screens, or a white-label requirement per partner.

---

### ADR-006 — Admin panel in Flutter web for v1
**Decision:** reuse the Flutter stack rather than introduce React.
**Consequences:** slower admin UX, larger web bundle, but one language and immediate reuse of models
and API clients. The team is also newer to React/TypeScript on the frontend.
**Reversal trigger:** admin surface past 15 screens, or a need for heavy data-grid interactions
(bulk food import editing is the likely trigger).

---

### ADR-007 — Health Connect / HealthKit, never Google Fit
**Context:** Google Fit APIs are supported only until the end of 2026; the Fitbit Web API turns down
September 2026; the Google Health API's scopes are all Restricted and require a privacy review with a
queue.
**Decision:** Health Connect (Android) + HealthKit (iOS) behind one interface, manual entry always
available. No cloud health integration in v1.
**Consequences:** Android-only automatic steps at launch (fine — Android-first anyway).

---

### ADR-008 — COACHING is a service tier, not a first-party product
**Context:** the pricing matrix contains both a ₹22,999 first-party coaching plan and a 30–40 %
partner commission. Doing both means competing with your own distribution channel, and the margin
after store fee, commission and GST leaves ~₹687/month to pay a coach (doc 12 §4).
**Decision:** platform sells BASIC and PRO. Coaching is sold *by partners*, on their own terms, with
Eatzify taking a platform fee.
**Consequences:** simpler entitlements, no coach payroll, aligned incentives with partners.
**Reversal trigger:** a partner network large enough that a premium first-party tier doesn't cannibalise it.

---

### ADR-009 — Coach access to client data is consent-scoped, not role-granted
**Context:** DPDP Act + Rules 2025. Sharing health data with a commercial third party on the basis of
an internal role flag is not a lawful basis.
**Decision:** a `consent_grant` row per (client, coach, scope, expiry). No grant, no data. Every read
audited.
**Consequences:** more schema and more UI (a client-facing "who can see my data" screen). This is the
single most important non-obvious decision in the whole system.

---

### ADR-010 — Money in integer paise; GST-inclusive display prices
**Decision:** `amount_paise BIGINT`. Catalogue prices are what the user pays (GST-inclusive). Net
revenue and tax are derived, stored explicitly on the transaction, never recomputed at read time.

---

### ADR-011 — Android-first launch, iOS at v1.2
**Context:** market, price sensitivity, Health Connect availability, and Play's India fee position.
**Decision:** ship Android. Keep the codebase iOS-clean (no Android-only packages in shared layers).

---

### ADR-012 — Own the food data loader; do not link AGPL packages
**Context:** the convenient `ifct2017` npm packages are AGPL-3.0 as of 1 May 2025; the network clause
would reach your server source.
**Decision:** import from the published IFCT 2017 tables and the open-access INDB, through your own
loader, with `source`/`source_code` recorded per row. Legal review of INDB reuse terms before launch.
