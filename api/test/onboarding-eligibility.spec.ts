import { UnprocessableEntityException } from '@nestjs/common';
import { ProfileService } from '../src/profile/profile.service';
import { ProfileAuditService } from '../src/profile/profile-audit.service';
import { OnboardingDto } from '../src/profile/dto/onboarding.dto';
import { UNDER_18, GOAL_WEIGHT_TOO_LOW } from '../src/plans/plan-copy';

/// docs/02 FR-1.2 and docs/05 §2. The two onboarding inputs that must be REFUSED rather than
/// stored and gated: an age under 18, and a goal weight that implies a BMI below 18.5.
///
/// The distinction matters. Every other gate (a condition, a high BMI) still stores the answers —
/// docs/05 §3 blocks plan generation, not the account, and discarding them would march the user
/// through the same questions to reach the same refusal. These two do not: FR-1.2 says "no profile
/// row is created, no health field is persisted", which for a minor is a DPDP obligation rather
/// than a UX preference.
function serviceWith() {
  const saved: Record<string, unknown>[] = [];

  const manager = {
    findOne: () => Promise.resolve(null),
    save: (_entity: unknown, row: Record<string, unknown>) => {
      saved.push(row);
      return Promise.resolve({ ...row, createdAt: new Date() });
    },
  };

  const service = new ProfileService(
    { findOne: () => Promise.resolve(null) } as never,
    { findOne: () => Promise.resolve(null) } as never,
    {} as never,
    {
      transaction: async (run: (m: unknown) => Promise<unknown>) =>
        run(manager),
    } as never,
    new ProfileAuditService({} as never),
  );

  return { service, saved };
}

function onboardingDto(overrides: Record<string, unknown> = {}): OnboardingDto {
  return {
    profile: {
      age_years: 32,
      height_cm: 172,
      weight_kg: 74.5,
      sex_at_birth: 'female',
      goal: 'lose_weight',
      activity: 'moderate',
      food_preference: 'vegetarian',
      meal_count: '4',
      lifestyle: 'desk_job',
      budget_tier: 'mid',
      ...overrides,
    },
    health_profile: {
      conditions: [],
      allergies: [],
      screened_special_diet: false,
      screened_insulin_or_kidney: false,
      screened_eating_disorder: false,
    },
    consents: [{ type: 'health_data_storage', granted: true }],
  } as unknown as OnboardingDto;
}

async function rejection(
  run: Promise<unknown>,
): Promise<{ code: string; user_message: string }> {
  try {
    await run;
  } catch (e) {
    const body = (e as UnprocessableEntityException).getResponse() as {
      error: { code: string; user_message: string };
    };
    return body.error;
  }
  throw new Error('expected the onboarding to be refused');
}

describe('POST /profile/onboarding — age (FR-1.2)', () => {
  it('should refuse onboarding when the applicant is under 18', async () => {
    const { service } = serviceWith();

    const error = await rejection(
      service.onboard(1, onboardingDto({ age_years: 17 })),
    );

    expect(error.code).toBe('AGE_INELIGIBLE');
  });

  /// "No profile row is created, no health field is persisted" is the half of FR-1.2 that is a
  /// privacy obligation: storing a minor's height, weight and conditions is the harm, and a gate
  /// flag on a stored row does not undo it.
  it('should persist nothing at all when the applicant is a minor', async () => {
    const { service, saved } = serviceWith();

    await rejection(service.onboard(1, onboardingDto({ age_years: 17 })));

    expect(saved).toHaveLength(0);
  });

  /// docs/05 §7 says "use verbatim; do not paraphrase". The under-18 string already existed in
  /// `plan-copy.ts` but nothing reached it: screening emitted `age_below_minimum` while the copy
  /// table was keyed `age_ineligible`, so the lookup fell through to the generic blocking-condition
  /// text — the wrong approved string, which is its own docs/05 violation.
  it('should answer with the approved under-18 copy verbatim when the applicant is a minor', async () => {
    const { service } = serviceWith();

    const error = await rejection(
      service.onboard(1, onboardingDto({ age_years: 17 })),
    );

    expect(error.user_message).toBe(UNDER_18);
  });

  it('should admit the applicant when they are exactly 18', async () => {
    const { service, saved } = serviceWith();

    await service.onboard(1, onboardingDto({ age_years: 18 }));

    expect(saved.length).toBeGreaterThan(0);
  });
});

describe('POST /profile/onboarding — goal weight (FR-1.5)', () => {
  /// docs/05 §2: "Goal weight implies BMI < 18.5 → reject at input with plain explanation. No
  /// override." At 1.72 m, 18.5 BMI is 54.7 kg, so 52 is under it.
  it('should refuse the goal weight when it implies a BMI under 18.5', async () => {
    const { service, saved } = serviceWith();

    const error = await rejection(
      service.onboard(1, onboardingDto({ goal_weight_kg: 52 })),
    );

    expect(error.code).toBe('VALIDATION_FAILED');
    expect(error.user_message).toBe(GOAL_WEIGHT_TOO_LOW);
    expect(saved).toHaveLength(0);
  });

  it('should admit the goal weight when it lands on a healthy BMI', async () => {
    const { service, saved } = serviceWith();

    await service.onboard(1, onboardingDto({ goal_weight_kg: 62 }));

    expect(saved.length).toBeGreaterThan(0);
  });

  it('should have no opinion when no goal weight was given', async () => {
    const { service, saved } = serviceWith();

    await service.onboard(1, onboardingDto());

    expect(saved.length).toBeGreaterThan(0);
  });
});
