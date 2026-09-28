import { RoleEnum } from '../roles/roles.enum';
import type { GrantScope } from './entities/coach-grant.entity';
import type { ClientMetrics } from '../clients/client-metrics.service';
import { ClientMetricsService } from '../clients/client-metrics.service';

/**
 * Who is asking, and what the person they are asking about allowed.
 *
 * Both halves are required for every decision in this file. docs/10 §1: "the level does not grant
 * access. The consent grant does. The level caps what a grant may contain."
 */
export type Access = {
  role: RoleEnum | undefined;
  scopes: readonly GrantScope[];
};

/// Everything the database can offer about one client, before anyone decides what may leave.
export type ClientFacts = {
  userId: number;
  name: string | null;
  ageYears: number | null;
  sexAtBirth: string | null;
  goal: string | null;
  heightCm: number | null;
  weightKg: number | null;
  weightChange30d: number | null;
  tier: string | null;
  conditions: string[] | null;
  allergies: string[] | null;
  /// The rest of what a health profile holds. Declared, never diagnosed.
  medications: string | null;
  digestiveSymptoms: string[] | null;
  injuries: string[] | null;
  /**
   * Every answer the PLAN was built from — how many meals, when they eat, how they live, what they
   * will not eat, what they can spend.
   *
   * None of it is medical, and all of it is what a nutritionist needs before writing a diet. A
   * coach who cannot see that somebody eats five times a day, works nights and will not touch
   * karela is guessing (D-205).
   */
  routine: Record<string, unknown> | null;
  metrics: ClientMetrics | null;
  grantExpiresAt: Date | null;
};

/// docs/12 §9's three states, plus the one docs/05 §6 forced a rename on.
export const CLIENT_STATUS = ['active', 'at_risk', 'no_recent_logs'] as const;
export type ClientStatus = (typeof CLIENT_STATUS)[number];

/**
 * One roster row. Every field optional and ABSENT when not permitted.
 *
 * Absent rather than null: a null `weight_kg` reads as "this person has no weight on file", which
 * is a claim about them. No key at all reads as "you were not shown this", which is a fact about
 * the grant.
 */
export type RosterRow = {
  client_user_id: number;
  name: string;
  scopes: GrantScope[];
  expires_at: string;
  tier?: string;
  age_band?: string;
  age_years?: number;
  goal?: string;
  adherence_pct?: number | null;
  streak_days?: number;
  last_logged_date?: string | null;
  days_since_last_log?: number | null;
  weight_kg?: number;
  weight_change_30d?: number | null;
  status?: ClientStatus;
};

export type ClientDetailView = RosterRow & {
  sex_at_birth?: string;
  height_cm?: number;
  conditions?: string[];
  allergies?: string[];
  medications?: string;
  digestive_symptoms?: string[];
  injuries?: string[];
  routine?: Record<string, unknown>;
};

/// Ten-year bands. docs/10 §2 gives an unverified coach an age BAND, and `basic` names the band
/// rather than the number — so a birthday never reaches someone whose grant did not include one.
export function ageBand(years: number): string {
  return `${Math.floor(years / 10) * 10}s`;
}

/// docs/10 §2: coach_l1 sees "first name + initial".
export function maskName(name: string, masked: boolean): string {
  if (!masked) return name;

  const [first = '', ...rest] = name.trim().split(/\s+/);
  const initial = rest.at(-1)?.[0];
  return initial ? `${first} ${initial}.` : first;
}

/**
 * The one place a client's fields are filtered.
 *
 * docs/10 §6, near-verbatim: "Field masking happens in a serialiser keyed by (viewer role, grant
 * scopes) — never by conditionals scattered through controllers. One place to audit, one place to
 * test." Every branch below cites the matrix row it implements, and `test/client-view.spec.ts` has
 * one case per row.
 *
 * The rule that holds everywhere in here: **a role only ever narrows.** There is no branch where a
 * higher level reveals something the grant did not carry.
 */
export abstract class ClientSerializer {
  /// A verified coach sees a name and an age; an affiliate sees an initial and a band.
  static isMasked(access: Access): boolean {
    return access.role === RoleEnum.coach_l1;
  }

  static rosterRow(facts: ClientFacts, access: Access): RosterRow {
    const masked = ClientSerializer.isMasked(access);
    const has = (scope: GrantScope) => access.scopes.includes(scope);

    const row: RosterRow = {
      client_user_id: facts.userId,
      name: maskName(facts.name ?? `Client ${facts.userId}`, masked),
      scopes: [...access.scopes],
      expires_at: (facts.grantExpiresAt ?? new Date(0)).toISOString(),
    };

    // `basic` — docs/10 §3: "display name, age band, goal, plan tier".
    if (has('basic')) {
      if (facts.ageYears !== null) {
        if (masked) row.age_band = ageBand(facts.ageYears);
        else row.age_years = facts.ageYears;
      }
      if (facts.goal !== null) row.goal = facts.goal;
      if (facts.tier !== null) row.tier = facts.tier;
    }

    // `progress` — docs/10 §3: "weight series, adherence %, steps, streaks". The matrix also puts
    // weight at ❌ for coach_l1, so the scope alone is not enough.
    if (has('progress') && !masked) {
      if (facts.weightKg !== null) row.weight_kg = facts.weightKg;
      row.weight_change_30d = facts.weightChange30d;

      if (facts.metrics !== null) {
        row.adherence_pct = facts.metrics.adherencePct;
        row.streak_days = facts.metrics.streakDays;
        row.last_logged_date = facts.metrics.lastLoggedDate;
        row.days_since_last_log = facts.metrics.daysSinceLastLog;
        row.status = statusFor(facts.metrics);
      }
    }

    return row;
  }

  static detail(facts: ClientFacts, access: Access): ClientDetailView {
    const view: ClientDetailView = ClientSerializer.rosterRow(facts, access);
    const masked = ClientSerializer.isMasked(access);
    const has = (scope: GrantScope) => access.scopes.includes(scope);

    // Sex and height are level 2 fields in docs/10 §2 and ride with `progress`, the scope a client
    // grants for "how am I doing".
    if (has('progress') && !masked) {
      if (facts.sexAtBirth !== null) view.sex_at_birth = facts.sexAtBirth;
      if (facts.heightCm !== null) view.height_cm = facts.heightCm;
    }

    /**
     * The eating-disorder screening answer is never filtered here — docs/10 §5.5 puts it beyond
     * every role and every grant, so it is never read into `facts` in the first place.
     *
     * D-205 moved this from coach_l3 to any verified coach.
     *
     * docs/10 §2 put medical conditions at ❌ for coach_l2 on the grounds that "a verified coach
     * with no coaching relationship has no need for a diabetes diagnosis". The premise does not
     * hold once a client has handed that coach a `health_conditions` grant: the client chose them
     * precisely to act on it, and a nutritionist who cannot see PCOS or a peanut allergy writes a
     * diet that could hurt somebody.
     *
     * The consent grant is still the whole gate. An affiliate reaches none of it at any level.
     */
    if (has('health_conditions') && !masked) {
      view.conditions = facts.conditions ?? [];
      view.allergies = facts.allergies ?? [];
      view.medications = facts.medications ?? '';
      view.digestive_symptoms = facts.digestiveSymptoms ?? [];
      view.injuries = facts.injuries ?? [];
    }

    // The answers the plan was built from. `progress` rather than `basic`: they describe how
    // somebody actually lives and eats, which is the same territory as what they logged.
    if (has('progress') && !masked && facts.routine !== null) {
      view.routine = facts.routine;
    }

    return view;
  }

  /// Whether this serialisation let a health field out, and therefore whether the read needs a
  /// `read_health` audit row (docs/10 §6). Asked once per request, not once per field.
  static carriedHealthField(row: RosterRow | ClientDetailView): boolean {
    return (
      'weight_kg' in row ||
      'adherence_pct' in row ||
      'conditions' in row ||
      'height_cm' in row
    );
  }
}

/**
 * docs/12 §9: "clients at risk (no log ≥3 days)".
 *
 * The third state is `no_recent_logs`, not "inactive". docs/05 §6 — "Never mark past days red as
 * 'Missed'. Use a neutral 'not logged'" — is about wording, and "Inactive" is a verdict on the
 * person where "no recent logs" is a fact about the diary. The coach learns the same thing either
 * way; only one of them would be quoted back at the client.
 */
function statusFor(metrics: ClientMetrics): ClientStatus {
  if (!ClientMetricsService.isAtRisk(metrics)) return 'active';

  const since = metrics.daysSinceLastLog;
  return since === null || since >= 7 ? 'no_recent_logs' : 'at_risk';
}
