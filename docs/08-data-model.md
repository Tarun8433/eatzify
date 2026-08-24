# 08 — Data Model (PostgreSQL 16)

Conventions: `snake_case`; UUID v7 primary keys (`id`); `created_at`/`updated_at TIMESTAMPTZ`;
soft delete only where a retention rule requires it (`deleted_at`); money as `BIGINT` paise;
every table with health data listed in doc 13's retention table.

## 1. Identity & profile

```sql
CREATE TYPE user_role AS ENUM ('client','coach','partner','support','admin','super_admin');

CREATE TABLE users (
  id              UUID PRIMARY KEY,
  phone_e164      TEXT UNIQUE NOT NULL,
  phone_hash      TEXT NOT NULL,              -- for trial-abuse checks without exposing the number
  email           TEXT UNIQUE,
  email_verified  BOOLEAN NOT NULL DEFAULT FALSE,
  phone_verified  BOOLEAN NOT NULL DEFAULT FALSE,
  display_name    TEXT NOT NULL,
  roles           user_role[] NOT NULL DEFAULT '{client}',
  status          TEXT NOT NULL DEFAULT 'active',   -- active|blocked|deleted
  is_demo         BOOLEAN NOT NULL DEFAULT FALSE,
  last_active_at  TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);
CREATE INDEX ON users (status) WHERE deleted_at IS NULL;
CREATE INDEX ON users (last_active_at DESC);

CREATE TABLE profiles (
  user_id       UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  dob           DATE NOT NULL,
  sex_at_birth  TEXT NOT NULL,                -- male|female|intersex_prefer_not_say
  height_cm     SMALLINT NOT NULL CHECK (height_cm BETWEEN 120 AND 220),
  city          TEXT,
  locale        TEXT NOT NULL DEFAULT 'en-IN',
  timezone      TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  CONSTRAINT adult_only CHECK (dob <= (CURRENT_DATE - INTERVAL '18 years'))
);

-- versioned: never UPDATE, always INSERT a new version
CREATE TABLE health_profiles (
  id               UUID PRIMARY KEY,
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  version          INT  NOT NULL,
  activity_level   TEXT NOT NULL,
  goal             TEXT NOT NULL,             -- fat_loss|muscle_gain|maintenance
  goal_weight_kg   NUMERIC(5,1),
  conditions       TEXT[] NOT NULL DEFAULT '{}',
  food_allergies   TEXT[] NOT NULL DEFAULT '{}',
  food_preference  TEXT NOT NULL,
  budget_tier      TEXT NOT NULL,
  lifestyle        TEXT NOT NULL,
  meal_count       TEXT NOT NULL,             -- '3'|'4'|'5_6'
  screening        JSONB NOT NULL DEFAULT '{}',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, version)
);

CREATE TABLE measurements (
  id            UUID PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,                -- weight|waist|bp_sys|bp_dia|hba1c
  value         NUMERIC(7,2) NOT NULL,
  unit          TEXT NOT NULL,
  diary_date    DATE NOT NULL,                -- diary day, not calendar day
  source        TEXT NOT NULL DEFAULT 'manual',
  is_suspect    BOOLEAN NOT NULL DEFAULT FALSE,   -- set when delta rule trips
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, kind, diary_date)
);
```

`is_suspect` + the `UNIQUE (user_id, kind, diary_date)` constraint together prevent the current
build's "−30.0 kg change" readout: one weight per day, and implausible jumps flagged and excluded
from trend and adjuster calculations.

## 2. Consent (the legal spine — see doc 13)

```sql
CREATE TABLE consents (
  id            UUID PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose       TEXT NOT NULL,   -- account|health_processing|coach_sharing|marketing|analytics
  notice_version TEXT NOT NULL,  -- which consent notice text they saw
  granted       BOOLEAN NOT NULL,
  scope         JSONB NOT NULL DEFAULT '{}',
  method        TEXT NOT NULL,   -- onboarding_checkbox|settings_toggle|coach_invite_accept
  ip_hash       TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);   -- append-only; withdrawal is a new row with granted = FALSE
CREATE INDEX ON consents (user_id, purpose, created_at DESC);

CREATE TABLE consent_grants (       -- resolved, queryable current state
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  grantee_id   UUID NOT NULL REFERENCES users(id),      -- coach or partner
  scope        TEXT[] NOT NULL,     -- basic|progress|plan_view|plan_edit|chat|health_conditions
  expires_at   TIMESTAMPTZ NOT NULL,
  revoked_at   TIMESTAMPTZ,
  source_consent_id UUID NOT NULL REFERENCES consents(id),
  UNIQUE (user_id, grantee_id)
);
```

## 3. Diet plans

```sql
CREATE TABLE rule_packs (
  version     TEXT PRIMARY KEY,       -- '1.0.0'
  content_hash TEXT NOT NULL,
  yaml        TEXT NOT NULL,          -- snapshot, so old plans stay explainable
  reviewed_by TEXT,
  activated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE diet_plans (
  id                 UUID PRIMARY KEY,
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  health_profile_id  UUID NOT NULL REFERENCES health_profiles(id),
  rule_pack_version  TEXT NOT NULL REFERENCES rule_packs(version),
  revision           INT  NOT NULL DEFAULT 1,
  status             TEXT NOT NULL,   -- draft|issued|active|superseded|expired
  valid_from         DATE NOT NULL,
  valid_to           DATE NOT NULL,
  target_kcal        INT NOT NULL,
  protein_g          NUMERIC(6,1) NOT NULL,
  carb_g             NUMERIC(6,1) NOT NULL,
  fat_g              NUMERIC(6,1) NOT NULL,
  fibre_g            NUMERIC(5,1) NOT NULL,
  sodium_mg          INT NOT NULL,
  input_snapshot     JSONB NOT NULL,
  trace              JSONB NOT NULL,
  warnings           JSONB NOT NULL DEFAULT '[]',
  generated_by       TEXT NOT NULL,   -- engine|coach_override
  overridden_by      UUID REFERENCES users(id),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, valid_from, revision)
);
CREATE UNIQUE INDEX one_active_plan ON diet_plans (user_id) WHERE status = 'active';

CREATE TABLE plan_meals (
  id            UUID PRIMARY KEY,
  plan_id       UUID NOT NULL REFERENCES diet_plans(id) ON DELETE CASCADE,
  slot          TEXT NOT NULL,       -- breakfast|mid_morning|lunch|evening|dinner|bedtime
  slot_order    SMALLINT NOT NULL,
  window_start  TIME, window_end TIME,
  target_kcal   INT NOT NULL
);

CREATE TABLE plan_items (
  id            UUID PRIMARY KEY,
  meal_id       UUID NOT NULL REFERENCES plan_meals(id) ON DELETE CASCADE,
  food_id       UUID REFERENCES foods(id),
  recipe_id     UUID REFERENCES recipes(id),
  quantity_g    NUMERIC(7,1) NOT NULL,
  measure_id    UUID REFERENCES household_measures(id),
  measure_qty   NUMERIC(4,2),
  is_alternate  BOOLEAN NOT NULL DEFAULT FALSE,
  alternate_of  UUID REFERENCES plan_items(id),
  CHECK (num_nonnulls(food_id, recipe_id) = 1)
);
```

## 4. Food database — with the validation the current build is missing

```sql
CREATE TABLE foods (
  id              UUID PRIMARY KEY,
  name_en         TEXT NOT NULL,
  name_hi         TEXT,
  synonyms        TEXT[] NOT NULL DEFAULT '{}',   -- regional names: 'chawal','bhaat','arisi'
  source          TEXT NOT NULL,                  -- ifct2017|indb|manual|branded
  source_code     TEXT,
  kcal_100g       NUMERIC(6,1) NOT NULL,
  protein_100g    NUMERIC(5,1) NOT NULL,
  carb_100g       NUMERIC(5,1) NOT NULL,
  fat_100g        NUMERIC(5,1) NOT NULL,
  fibre_100g      NUMERIC(5,1) NOT NULL DEFAULT 0,
  sugar_100g      NUMERIC(5,1) NOT NULL DEFAULT 0,
  sat_fat_100g    NUMERIC(5,1) NOT NULL DEFAULT 0,
  sodium_mg_100g  NUMERIC(7,1) NOT NULL DEFAULT 0,
  gi_value        SMALLINT,
  tags            TEXT[] NOT NULL DEFAULT '{}',
  status          TEXT NOT NULL DEFAULT 'draft',  -- draft|reviewed|published|retired
  reviewed_by     UUID REFERENCES users(id),
  created_by      UUID REFERENCES users(id),
  is_demo         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Atwater consistency: stated kcal must be within 10% of macro-derived kcal
  CONSTRAINT atwater_consistent CHECK (
    kcal_100g = 0 OR
    abs(kcal_100g - (protein_100g*4 + carb_100g*4 + fat_100g*9)) <= 0.10 * GREATEST(kcal_100g, 1)
  ),
  CONSTRAINT macro_mass_sane CHECK (protein_100g + carb_100g + fat_100g <= 100),
  CONSTRAINT nonneg CHECK (protein_100g >= 0 AND carb_100g >= 0 AND fat_100g >= 0)
);
CREATE UNIQUE INDEX ON foods (lower(name_en)) WHERE status <> 'retired';
CREATE INDEX ON foods USING GIN (tags);
CREATE INDEX ON foods USING GIN (to_tsvector('simple', name_en || ' ' || coalesce(name_hi,'') || ' ' || array_to_string(synonyms,' ')));
```

**Both rows currently in your production nutrition DB fail this constraint.** "CHAUHAN4" states
34 kcal but its macros (P4/C5/F1) derive to 45 kcal — 32 % off. "vishwash" states 134 kcal against
107 derived — 25 % off. That constraint would have rejected both at insert, along with the placeholder
names, which the unique-name-plus-review-workflow also stops from reaching users.

```sql
CREATE TABLE household_measures (
  id           UUID PRIMARY KEY,
  food_id      UUID REFERENCES foods(id) ON DELETE CASCADE,
  recipe_id    UUID REFERENCES recipes(id) ON DELETE CASCADE,
  label_en     TEXT NOT NULL,          -- 'katori (medium)','roti','glass','tsp'
  label_hi     TEXT,
  grams        NUMERIC(6,1) NOT NULL,
  is_default   BOOLEAN NOT NULL DEFAULT FALSE,
  CHECK (num_nonnulls(food_id, recipe_id) = 1)
);

CREATE TABLE recipes (
  id            UUID PRIMARY KEY,
  name_en       TEXT NOT NULL,
  name_hi       TEXT,
  yield_g       NUMERIC(7,1) NOT NULL,
  cook_minutes  SMALLINT,
  method        TEXT,
  tags          TEXT[] NOT NULL DEFAULT '{}',
  status        TEXT NOT NULL DEFAULT 'draft',
  source        TEXT NOT NULL
);
CREATE TABLE recipe_ingredients (
  recipe_id  UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  food_id    UUID NOT NULL REFERENCES foods(id),
  grams      NUMERIC(7,1) NOT NULL,
  PRIMARY KEY (recipe_id, food_id)
);
```

Recipe nutrition is **derived** from ingredients (a materialised view refreshed on change), never
hand-entered. Hand-entered composite nutrition is how databases rot.

## 5. Entitlements (replacing per-food "target audience")

```sql
CREATE TABLE plan_catalogue (
  id            UUID PRIMARY KEY,
  tier          TEXT NOT NULL,        -- FREE|BASIC|PRO
  duration_months SMALLINT NOT NULL,  -- 0 for free, 3|6|9|12
  price_paise   BIGINT NOT NULL,
  mrp_paise     BIGINT,
  badge         TEXT,                 -- most_popular|best_value
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (tier, duration_months)
);

CREATE TABLE entitlement_defs (
  key         TEXT PRIMARY KEY,       -- 'plan.regenerate_per_day','coach.chat','export.pdf'
  kind        TEXT NOT NULL,          -- boolean|quota
  description TEXT NOT NULL
);
CREATE TABLE tier_entitlements (
  tier        TEXT NOT NULL,
  key         TEXT NOT NULL REFERENCES entitlement_defs(key),
  value       JSONB NOT NULL,
  PRIMARY KEY (tier, key)
);
```

## 6. Subscriptions & money

```sql
CREATE TABLE subscriptions (
  id                UUID PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES users(id),
  tier              TEXT NOT NULL,
  catalogue_id      UUID NOT NULL REFERENCES plan_catalogue(id),
  status            TEXT NOT NULL,     -- trialing|active|past_due|grace|expired|cancelled
  provider          TEXT NOT NULL,     -- play|razorpay|manual
  provider_ref      TEXT,
  starts_at         TIMESTAMPTZ NOT NULL,
  ends_at           TIMESTAMPTZ NOT NULL,
  auto_renew        BOOLEAN NOT NULL DEFAULT FALSE,
  requires_afa      BOOLEAN NOT NULL DEFAULT FALSE,  -- price > ₹15,000 (RBI 2026)
  cancelled_at      TIMESTAMPTZ,
  trial_ends_at     TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_live_sub ON subscriptions (user_id)
  WHERE status IN ('trialing','active','past_due','grace');

CREATE TABLE payments (
  id                UUID PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES users(id),
  subscription_id   UUID REFERENCES subscriptions(id),
  provider          TEXT NOT NULL,
  provider_txn_id   TEXT UNIQUE,
  idempotency_key   TEXT UNIQUE NOT NULL,
  gross_paise       BIGINT NOT NULL,
  tax_paise         BIGINT NOT NULL,
  net_paise         BIGINT NOT NULL,
  store_fee_paise   BIGINT NOT NULL DEFAULT 0,
  status            TEXT NOT NULL,     -- created|authorized|captured|failed|refunded
  raw               JSONB,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 7. Coach, partner, commission

```sql
CREATE TABLE coach_profiles (
  user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  headline       TEXT,
  specialisations TEXT[] NOT NULL DEFAULT '{}',
  languages      TEXT[] NOT NULL DEFAULT '{}',
  experience_years SMALLINT,
  verified_at    TIMESTAMPTZ,
  verified_attributes JSONB NOT NULL DEFAULT '{}',  -- what we actually checked
  level          SMALLINT NOT NULL DEFAULT 1        -- 1 affiliate | 2 verified | 3 coaching
);

CREATE TABLE coach_assignments (
  id           UUID PRIMARY KEY,
  coach_id     UUID NOT NULL REFERENCES users(id),
  client_id    UUID NOT NULL REFERENCES users(id),
  status       TEXT NOT NULL,          -- invited|active|paused|ended
  grant_id     UUID REFERENCES consent_grants(id),
  started_at   TIMESTAMPTZ, ended_at TIMESTAMPTZ,
  UNIQUE (coach_id, client_id)
);

CREATE TABLE partners (
  user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  kind           TEXT NOT NULL,        -- coach|gym|consultant|influencer
  referral_code  TEXT UNIQUE NOT NULL,
  commission_tier TEXT NOT NULL DEFAULT 'standard',
  kyc_status     TEXT NOT NULL DEFAULT 'pending',
  pan_last4      TEXT,                 -- never store full PAN in the app DB
  gstin          TEXT,
  payout_method  TEXT,
  min_payout_paise BIGINT NOT NULL DEFAULT 100000
);

CREATE TABLE attributions (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  partner_id  UUID NOT NULL REFERENCES partners(user_id),
  code_used   TEXT NOT NULL,
  channel     TEXT NOT NULL,           -- code|link|qr
  locked_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);  -- immutable by policy; enforce with a REVOKE UPDATE grant

CREATE TABLE commission_entries (
  id            UUID PRIMARY KEY,
  partner_id    UUID NOT NULL REFERENCES partners(user_id),
  payment_id    UUID NOT NULL REFERENCES payments(id),
  kind          TEXT NOT NULL,         -- first_purchase|renewal|upsell|reversal
  base_paise    BIGINT NOT NULL,
  rate_bps      INT NOT NULL,          -- basis points, avoids float
  amount_paise  BIGINT NOT NULL,
  status        TEXT NOT NULL,         -- accrued|held|payable|paid|reversed
  hold_until    TIMESTAMPTZ,
  payout_id     UUID REFERENCES payouts(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE payouts (
  id            UUID PRIMARY KEY,
  partner_id    UUID NOT NULL REFERENCES partners(user_id),
  period_start  DATE NOT NULL, period_end DATE NOT NULL,
  gross_paise   BIGINT NOT NULL,
  tds_paise     BIGINT NOT NULL DEFAULT 0,
  net_paise     BIGINT NOT NULL,
  status        TEXT NOT NULL,         -- pending|processing|paid|failed
  utr           TEXT,
  paid_at       TIMESTAMPTZ
);
```

## 8. Logs, notifications, tickets, audit

```sql
CREATE TABLE food_logs (
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  diary_date   DATE NOT NULL,
  slot         TEXT NOT NULL,
  food_id      UUID REFERENCES foods(id),
  recipe_id    UUID REFERENCES recipes(id),
  custom_name  TEXT,
  quantity_g   NUMERIC(7,1) NOT NULL,
  kcal         NUMERIC(7,1) NOT NULL,
  protein_g    NUMERIC(6,1) NOT NULL, carb_g NUMERIC(6,1) NOT NULL, fat_g NUMERIC(6,1) NOT NULL,
  source       TEXT NOT NULL DEFAULT 'manual',   -- manual|photo|barcode|plan_tick
  confidence   NUMERIC(3,2),
  was_corrected BOOLEAN,
  locked_at    TIMESTAMPTZ,                       -- editable 48h then locked
  logged_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON food_logs (user_id, diary_date);

CREATE TABLE water_logs (LIKE food_logs INCLUDING ALL);  -- illustrative; real table: user, diary_date, ml, logged_at
CREATE TABLE step_logs (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  diary_date DATE NOT NULL, steps INT NOT NULL,
  provider TEXT NOT NULL,          -- health_connect|healthkit|manual
  PRIMARY KEY (user_id, diary_date)
);

CREATE TABLE audit_log (
  id          BIGSERIAL PRIMARY KEY,
  actor_id    UUID REFERENCES users(id),
  actor_role  TEXT NOT NULL,
  action      TEXT NOT NULL,        -- read_health|export|override_plan|change_price|grant_revoke
  subject_id  UUID,
  resource    TEXT NOT NULL,
  meta        JSONB NOT NULL DEFAULT '{}',
  ip_hash     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- append only
REVOKE UPDATE, DELETE ON audit_log FROM app_user;
```

## 9. Row-level scoping

Enable RLS on `health_profiles`, `measurements`, `diet_plans`, `food_logs`, `coach_assignments`.
Policy shape:
```sql
CREATE POLICY client_own ON measurements
  USING (user_id = current_setting('app.user_id')::uuid);
CREATE POLICY coach_granted ON measurements
  USING (EXISTS (SELECT 1 FROM consent_grants g
                 WHERE g.user_id = measurements.user_id
                   AND g.grantee_id = current_setting('app.user_id')::uuid
                   AND g.revoked_at IS NULL AND g.expires_at > now()
                   AND 'progress' = ANY(g.scope)));
```
Application-layer checks are the primary defence; RLS is the seatbelt. Both.

## 10. Seed & demo data

Every table with user-visible content carries `is_demo`. The metrics rollup filters it out. The
production deploy pipeline refuses to run any seeder. Your current dashboard shows ₹1,24,560 monthly
revenue against 4 total users and 1 active subscription — that mixture is exactly what this prevents.
