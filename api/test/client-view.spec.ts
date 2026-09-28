import {
  ClientSerializer,
  ageBand,
  maskName,
  type Access,
  type ClientFacts,
} from '../src/coach/client-view.serializer';
import { RoleEnum } from '../src/roles/roles.enum';
import type { GrantScope } from '../src/coach/entities/coach-grant.entity';
import type { ClientMetrics } from '../src/clients/client-metrics.service';

/**
 * docs/10 §2, the field matrix, as executable rows.
 *
 * §6 asks for exactly this: "Field masking happens in a serialiser keyed by (viewer role, grant
 * scopes) … Write a test per row of the matrix above. That test file is your compliance evidence."
 * This is that file.
 *
 * The property every case defends: **a role only ever narrows what a grant already allowed.** No
 * test below should be able to reach a field by raising a level alone.
 */

const METRICS: ClientMetrics = {
  avgKcal: 1740,
  avgProteinG: 96,
  targetKcal: 1859,
  targetProteinG: 125,
  adherencePct: 64,
  daysLogged: 18,
  windowDays: 28,
  streakDays: 4,
  lastLoggedDate: '2026-09-14',
  daysSinceLastLog: 1,
};

const FACTS: ClientFacts = {
  userId: 9,
  name: 'Ritu Agarwal',
  ageYears: 34,
  sexAtBirth: 'female',
  goal: 'fat_loss',
  heightCm: 165,
  weightKg: 72,
  weightChange30d: -1.4,
  tier: 'PRO',
  conditions: ['pcos'],
  allergies: ['peanut'],
  medications: 'metformin',
  digestiveSymptoms: ['acidity'],
  injuries: [],
  routine: {
    meal_count: '5_6',
    lifestyle: 'night_shift',
    food_dislikes: 'karela',
  },
  metrics: METRICS,
  grantExpiresAt: new Date('2027-01-01T00:00:00Z'),
};

function access(role: RoleEnum, scopes: GrantScope[]): Access {
  return { role, scopes };
}

const L2_FULL = access(RoleEnum.coach_l2, ['basic', 'progress', 'plan_view']);
const L3_FULL = access(RoleEnum.coach_l3, [
  'basic',
  'progress',
  'plan_view',
  'health_conditions',
]);

describe('matrix row: display name', () => {
  /// `| Display name | ✅ | 🔒 first name + initial | ✅ | ✅ |`
  it('should show the full name to a verified coach', () => {
    expect(ClientSerializer.rosterRow(FACTS, L2_FULL).name).toBe(
      'Ritu Agarwal',
    );
  });

  it('should mask the name to first name and initial for an affiliate', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l1, ['basic']),
    );

    expect(row.name).toBe('Ritu A.');
  });

  it('should leave a single-word name whole rather than inventing an initial', () => {
    expect(maskName('Ritu', true)).toBe('Ritu');
  });
});

describe('matrix row: age', () => {
  /// `| Age | ✅ | 📊 band | ✅ | ✅ |` — and docs/10 §3's `basic` scope names the BAND, not the
  /// number, so the exact age needs the level as well as the scope.
  it('should give an affiliate a band and never a birthday', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l1, ['basic']),
    );

    expect(row.age_band).toBe('30s');
    expect(row.age_years).toBeUndefined();
  });

  it('should give a verified coach the number', () => {
    const row = ClientSerializer.rosterRow(FACTS, L2_FULL);

    expect(row.age_years).toBe(34);
    expect(row.age_band).toBeUndefined();
  });

  it('should band by decade', () => {
    expect(ageBand(19)).toBe('10s');
    expect(ageBand(30)).toBe('30s');
    expect(ageBand(39)).toBe('30s');
  });
});

describe('matrix row: weight, current and history', () => {
  /// `| Weight (current) | ✅ | ❌ | ✅ | ✅ |` and the same shape for weight history.
  it('should show weight and the 30-day change under a progress grant', () => {
    const row = ClientSerializer.rosterRow(FACTS, L2_FULL);

    expect(row.weight_kg).toBe(72);
    expect(row.weight_change_30d).toBe(-1.4);
  });

  /// Absent, not null. A null weight reads as "this person has no weight on file", which is a
  /// claim about them; no key at all reads as "you were not shown this".
  it('should omit weight entirely without a progress grant', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l2, ['basic']),
    );

    expect('weight_kg' in row).toBe(false);
    expect('weight_change_30d' in row).toBe(false);
  });

  it('should refuse weight to an affiliate even with the scope', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l1, ['basic', 'progress']),
    );

    expect('weight_kg' in row).toBe(false);
  });
});

describe('matrix row: food logs and adherence', () => {
  /// `| Food logs | ✅ | ❌ | 📊 adherence % | ✅ |` — the aggregate, not the diary.
  it('should show the adherence figure and the streak under a progress grant', () => {
    const row = ClientSerializer.rosterRow(FACTS, L2_FULL);

    expect(row.adherence_pct).toBe(64);
    expect(row.streak_days).toBe(4);
  });

  it('should show nothing about logging to an affiliate', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l1, ['basic', 'progress']),
    );

    expect('adherence_pct' in row).toBe(false);
    expect('streak_days' in row).toBe(false);
  });

  /// docs/02 FR-4.2 wants "a count not a shame badge". A client who has never logged has no
  /// figure, and 0 % would be a verdict rather than a measurement.
  it('should carry a null adherence rather than zero for somebody who never logged', () => {
    const row = ClientSerializer.rosterRow(
      {
        ...FACTS,
        metrics: {
          ...METRICS,
          adherencePct: null,
          daysLogged: 0,
          streakDays: 0,
          lastLoggedDate: null,
          daysSinceLastLog: null,
        },
      },
      L2_FULL,
    );

    expect(row.adherence_pct).toBeNull();
  });
});

describe('matrix row: medical conditions', () => {
  /// `| Medical conditions | ✅ | ❌ | ❌ | ✅🔍 |` — the level AND the grant, not either. The doc:
  /// "A verified coach with no coaching relationship has no need for a diabetes diagnosis, and
  /// giving it to them is processing without a purpose."
  it('should show conditions to a coaching partner who was granted them', () => {
    const view = ClientSerializer.detail(FACTS, L3_FULL);

    expect(view.conditions).toEqual(['pcos']);
    expect(view.allergies).toEqual(['peanut']);
  });

  /// D-205 moved this line. A client who hands a nutritionist a `health_conditions` grant chose
  /// them precisely to act on it, and a diet written without seeing PCOS or a peanut allergy can
  /// hurt somebody.
  it('should show conditions to a verified coach the client granted them to', () => {
    const view = ClientSerializer.detail(
      FACTS,
      access(RoleEnum.coach_l2, ['basic', 'progress', 'health_conditions']),
    );

    expect(view.conditions).toEqual(['pcos']);
    expect(view.medications).toBe('metformin');
    expect(view.injuries).toEqual([]);
  });

  /// The consent grant is still the whole gate. No grant, nothing — at any level.
  it('should refuse conditions without the grant, whatever the level', () => {
    const view = ClientSerializer.detail(
      FACTS,
      access(RoleEnum.coach_l3, ['basic', 'progress']),
    );

    expect('conditions' in view).toBe(false);
    expect('medications' in view).toBe(false);
  });

  /// An affiliate has no coaching relationship at all, so the level cap still bites here.
  it('should refuse conditions to an affiliate even with the grant', () => {
    const view = ClientSerializer.detail(
      FACTS,
      access(RoleEnum.coach_l1, ['basic', 'health_conditions']),
    );

    expect('conditions' in view).toBe(false);
  });

  /// docs/10 §5.5 puts the eating-disorder screen beyond every role and every grant. It is not
  /// filtered — the query never asks for it, so it cannot reach this file to be filtered.
  it('should carry no screening answer at any level', () => {
    const view = ClientSerializer.detail(FACTS, L3_FULL);

    expect(JSON.stringify(view)).not.toContain('screened');
  });

  /// The answers a diet is written from: how many meals, when, what they will not eat. Not
  /// medical, and useless to withhold from somebody writing the plan.
  it('should carry the routine answers under a progress grant', () => {
    const view = ClientSerializer.detail(FACTS, L2_FULL);

    expect(view.routine).toMatchObject({
      meal_count: '5_6',
      lifestyle: 'night_shift',
      food_dislikes: 'karela',
    });
  });

  it('should carry no routine answers without that grant', () => {
    const view = ClientSerializer.detail(
      FACTS,
      access(RoleEnum.coach_l2, ['basic']),
    );

    expect('routine' in view).toBe(false);
  });
});

describe('matrix row: sex at birth', () => {
  /// `| Sex at birth | ✅ | ❌ | ✅ | ✅ |`
  it('should show sex to a verified coach and never to an affiliate', () => {
    expect(ClientSerializer.detail(FACTS, L2_FULL).sex_at_birth).toBe('female');
    expect(
      'sex_at_birth' in
        ClientSerializer.detail(
          FACTS,
          access(RoleEnum.coach_l1, ['basic', 'progress']),
        ),
    ).toBe(false);
  });
});

describe('matrix row: goal and plan tier', () => {
  /// Both are in docs/10 §3's `basic` scope: "display name, age band, goal, plan tier".
  it('should show the goal and the tier under a basic grant', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l2, ['basic']),
    );

    expect(row.goal).toBe('fat_loss');
    expect(row.tier).toBe('PRO');
  });

  it('should show neither without one', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l2, ['progress']),
    );

    expect('goal' in row).toBe(false);
    expect('tier' in row).toBe(false);
  });
});

describe('an affiliate with no scopes at all', () => {
  /// `SCOPES_BY_ROLE` gives coach_l1 nothing, which is the ordinary state for a referrer. They get
  /// a masked name and not one fact beyond it.
  it('should return a name and nothing else', () => {
    const view = ClientSerializer.detail(FACTS, access(RoleEnum.coach_l1, []));

    expect(view.name).toBe('Ritu A.');
    expect(Object.keys(view).sort()).toEqual([
      'client_user_id',
      'expires_at',
      'name',
      'scopes',
    ]);
  });
});

describe('deciding whether a read was a health read', () => {
  /// docs/10 §6 wants health reads audited. A read that carried a name and a goal is not one, and
  /// logging it anyway fills the trail until the rows that matter stop standing out.
  it('should not call a name-and-goal read a health read', () => {
    const row = ClientSerializer.rosterRow(
      FACTS,
      access(RoleEnum.coach_l2, ['basic']),
    );

    expect(ClientSerializer.carriedHealthField(row)).toBe(false);
  });

  it('should call a read carrying weight or adherence a health read', () => {
    expect(
      ClientSerializer.carriedHealthField(
        ClientSerializer.rosterRow(FACTS, L2_FULL),
      ),
    ).toBe(true);
  });

  it('should call a read carrying conditions a health read', () => {
    expect(
      ClientSerializer.carriedHealthField(
        ClientSerializer.detail(FACTS, L3_FULL),
      ),
    ).toBe(true);
  });
});

describe('the status a coach sees (docs/12 §9)', () => {
  const statusFor = (daysSinceLastLog: number | null) =>
    ClientSerializer.rosterRow(
      { ...FACTS, metrics: { ...METRICS, daysSinceLastLog } },
      L2_FULL,
    ).status;

  it('should call somebody who logged recently active', () => {
    expect(statusFor(0)).toBe('active');
    expect(statusFor(2)).toBe('active');
  });

  /// docs/12 §9: "clients at risk (no log ≥3 days)".
  it('should call somebody at risk from three days', () => {
    expect(statusFor(3)).toBe('at_risk');
    expect(statusFor(6)).toBe('at_risk');
  });

  /// docs/05 §6 is about wording: "Use a neutral 'not logged'". "Inactive" is a verdict on the
  /// person; "no recent logs" is a fact about the diary. The coach learns the same thing.
  it('should state a long absence as a logging fact, never as a verdict', () => {
    expect(statusFor(7)).toBe('no_recent_logs');
    expect(statusFor(null)).toBe('no_recent_logs');
  });
});
