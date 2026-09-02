import { UnprocessableEntityException } from '@nestjs/common';
import { ProfileService } from '../src/profile/profile.service';
import { PatchHealthDto } from '../src/profile/dto/patch-health.dto';
import { ProfileAuditService } from '../src/profile/profile-audit.service';

/// Unit-level: the merge and re-gate rules of `PATCH /profile/health`, without a database.
/// The round-trip through postgres is covered by the live checks in docs/PROJECT-STATE.md.
function serviceWith(
  current: Record<string, unknown> | null,
  profile: Record<string, unknown>,
) {
  const saved: Record<string, unknown>[] = [];

  const audited: Record<string, unknown>[] = [];

  // The write and its audit row share a transaction now, so a fake manager records both.
  const manager = {
    save: async (_entity: unknown, row: Record<string, unknown>) => {
      if (Array.isArray(row)) {
        audited.push(...row);
        return row;
      }
      saved.push(row);
      return { ...row, createdAt: new Date() };
    },
  };

  const service = new ProfileService(
    { findOne: async () => profile } as never,
    {
      findOne: async () => current,
      save: async (row: Record<string, unknown>) => {
        saved.push(row);
        return { ...row, createdAt: new Date() };
      },
    } as never,
    {} as never,
    {
      transaction: async (run: (m: unknown) => Promise<unknown>) =>
        run(manager),
    } as never,
    new ProfileAuditService({} as never),
  );

  return { service, saved, audited };
}

const PROFILE = { ageYears: 32, heightCm: 172, weightKg: '74.50' };
const V1 = {
  version: 1,
  conditions: ['prediabetes'],
  allergies: ['peanut'],
  screenedSpecialDiet: false,
  screenedInsulinOrKidney: false,
  screenedEatingDisorder: false,
  gates: [],
};

describe('PATCH /profile/health', () => {
  it('refuses before onboarding, with a server-authored message', async () => {
    const { service } = serviceWith(null, PROFILE);

    await expect(
      service.patchHealth(1, {} as PatchHealthDto),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
  });

  it('writes a new version rather than mutating the current one', async () => {
    const { service, saved } = serviceWith(V1, PROFILE);

    const result = await service.patchHealth(1, { allergies: ['milk'] });

    expect(result.version).toBe(2);
    expect(saved).toHaveLength(1);
  });

  it('carries omitted fields forward instead of clearing them', async () => {
    const { service } = serviceWith(V1, PROFILE);

    // Only allergies are sent — a declared condition must not vanish because it went unmentioned.
    const result = await service.patchHealth(1, { allergies: ['milk', 'soy'] });

    expect(result.conditions).toEqual(['prediabetes']);
    expect(result.allergies).toEqual(['milk', 'soy']);
  });

  it('re-fires the docs/05 §3 gates when an edit adds a blocking condition', async () => {
    const { service } = serviceWith(V1, PROFILE);

    const result = await service.patchHealth(1, { conditions: ['ckd'] });

    expect(result.gates).toContain('ckd');
  });

  it('clears a gate when the condition that caused it is removed', async () => {
    const gated = { ...V1, conditions: ['ckd'], gates: ['ckd'] };
    const { service } = serviceWith(gated, PROFILE);

    const result = await service.patchHealth(1, {
      conditions: ['prediabetes'],
    });

    expect(result.gates).toEqual([]);
  });

  it('an explicit empty array clears, unlike an omitted field', async () => {
    const { service } = serviceWith(V1, PROFILE);

    const result = await service.patchHealth(1, { allergies: [] });

    expect(result.allergies).toEqual([]);
    expect(result.conditions).toEqual(['prediabetes']);
  });
});

const V1_PROFILE = {
  id: 1,
  userId: 1,
  ageYears: 32,
  heightCm: 172,
  weightKg: '74.50',
  goalWeightKg: null,
  sexAtBirth: 'female',
  goal: 'fat_loss',
  activity: 'moderate',
  foodPreference: 'veg',
  mealCount: '3',
  lifestyle: 'office',
  budgetTier: 'medium',
};

function profileServiceWith(
  profile: Record<string, unknown> | null,
  health: Record<string, unknown> | null,
) {
  const healthSaves: Record<string, unknown>[] = [];
  const profileSaves: Record<string, unknown>[] = [];

  const service = new ProfileService(
    {
      findOne: async () => profile,
      save: async (row: Record<string, unknown>) => {
        profileSaves.push(row);
        return row;
      },
    } as never,
    {
      findOne: async () => health,
      save: async (row: Record<string, unknown>) => {
        healthSaves.push(row);
        return { ...row, createdAt: new Date() };
      },
    } as never,
    {} as never,
    {
      transaction: async (run: (m: unknown) => Promise<unknown>) =>
        run({
          save: async (_entity: unknown, row: Record<string, unknown>) => {
            if (Array.isArray(row)) return row;
            if ('version' in row) {
              healthSaves.push(row);
            } else {
              profileSaves.push(row);
            }
            return { ...row, createdAt: new Date() };
          },
        }),
    } as never,
    new ProfileAuditService({} as never),
  );

  return { service, healthSaves, profileSaves };
}

describe('PATCH /profile', () => {
  it('refuses before onboarding', async () => {
    const { service } = profileServiceWith(null, null);

    await expect(
      service.patchProfile(1, { goal: 'maintenance' }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
  });

  it('carries omitted fields forward', async () => {
    const { service } = profileServiceWith(V1_PROFILE, V1);

    const result = await service.patchProfile(1, { goal: 'maintenance' });

    expect(result.profile.goal).toBe('maintenance');
    expect(result.profile.activity).toBe('moderate');
    expect(result.profile.age_years).toBe(32);
  });

  it('re-gates when weight drops to an unsafe BMI', async () => {
    const { service } = profileServiceWith(V1_PROFILE, V1);

    // 44 kg at 172 cm is a BMI of ~14.9 — docs/05 §3 blocks below 16.
    const result = await service.patchProfile(1, { weight_kg: 44 });

    expect(result.health_profile?.gates).toContain('bmi_below_16');
    expect(result.health_profile?.version).toBe(2);
  });

  it('does not spawn a health-profile version for a non-clinical field', async () => {
    const { service, healthSaves } = profileServiceWith(V1_PROFILE, V1);

    await service.patchProfile(1, { budget_tier: 'low' });

    expect(healthSaves).toHaveLength(0);
  });

  it('clears a BMI gate when weight returns to a safe range', async () => {
    const gated = { ...V1, gates: ['bmi_below_16'] };
    const { service } = profileServiceWith(
      { ...V1_PROFILE, weightKg: '44.00' },
      gated,
    );

    const result = await service.patchProfile(1, { weight_kg: 74.5 });

    expect(result.health_profile?.gates).toEqual([]);
  });
});
