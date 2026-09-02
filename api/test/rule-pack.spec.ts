/**
 * The loader is the boundary that keeps the engine pure. Its job is to refuse a bad pack at boot —
 * these tests assert it refuses, because a silently-accepted malformed pack is the docs/05 §1
 * failure mode with extra steps.
 */
import { join } from 'node:path';
import { EngineService } from '../src/modules/engine';
import {
  RulePackError,
  listPackVersions,
  loadAllRulePacks,
  loadRulePack,
} from '../src/modules/engine';
import { rulePackSchema } from '../src/modules/engine';

const PACK_DIR = join(__dirname, '..', 'config', 'rule-packs');

describe('rule pack discovery and loading', () => {
  it('finds v1.0.0 on disk', () => {
    expect(listPackVersions(PACK_DIR)).toContain('1.0.0');
  });

  it('loads and validates the shipped pack', () => {
    const pack = loadRulePack(PACK_DIR, '1.0.0');
    expect(pack.version).toBe('1.0.0');
    expect(pack.energy.bmr.formula).toBe('mifflin_st_jeor');
    expect(pack.macros.ibw_bmi_reference).toBe(23.0);
  });

  it('loads every pack in the directory', () => {
    expect(loadAllRulePacks(PACK_DIR).size).toBeGreaterThanOrEqual(1);
  });

  it('reports a missing file rather than returning a partial pack', () => {
    expect(() => loadRulePack(PACK_DIR, '9.9.9')).toThrow(RulePackError);
  });

  it('reports an empty pack directory', () => {
    expect(() =>
      loadAllRulePacks(join(__dirname, 'fixtures-does-not-exist')),
    ).toThrow();
  });
});

describe('schema rejects packs that would produce unsafe plans', () => {
  const base = loadRulePack(PACK_DIR, '1.0.0') as unknown as Record<
    string,
    unknown
  >;
  const mutate = (patch: (p: any) => void): unknown => {
    const clone = JSON.parse(JSON.stringify(base));
    patch(clone);
    return clone;
  };
  const errorsFor = (value: unknown): string => {
    const result = rulePackSchema.safeParse(value);
    expect(result.success).toBe(false);
    return result.success
      ? ''
      : result.error.issues.map((i) => i.message).join('; ');
  };

  it('rejects a reduced deficit ceiling looser than the default', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.safety.max_deficit_pct_reduced = 0.5;
        }),
      ),
    ).toMatch(/must not exceed max_deficit_pct_default/);
  });

  it('rejects a meal pattern that does not sum to 1.0', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.meals.patterns['4'][0].pct = 0.9;
        }),
      ),
    ).toMatch(/sums to .*expected 1\.000/);
  });

  it('rejects a hypertension sodium cap looser than the default', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.macros.sodium.max_mg_hypertension = 5000;
        }),
      ),
    ).toMatch(/max_mg_hypertension must not exceed max_mg_default/);
  });

  it('rejects a tightened saturated-fat cap that is not tighter', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.macros.fat.saturated_max_pct_tightened = 0.9;
        }),
      ),
    ).toMatch(/saturated_max_pct_tightened must not exceed/);
  });

  it('rejects an inverted fibre band and an inverted water band', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.macros.fibre.min_g = 99;
        }),
      ),
    ).toMatch(/fibre min_g/);
    expect(
      errorsFor(
        mutate((p) => {
          p.macros.water.min_ml = 9000;
        }),
      ),
    ).toMatch(/water min_ml/);
  });

  it('rejects a protein rate whose default sits outside its own range', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.macros.protein.rate_g_per_kg_abw.fat_loss.default = 9;
        }),
      ),
    ).toMatch(/min <= default <= max/);
  });

  it('rejects a non-semver version and an unknown BMR formula', () => {
    expect(
      errorsFor(
        mutate((p) => {
          p.version = '1.0';
        }),
      ),
    ).toMatch(/semver/);
    expect(
      errorsFor(
        mutate((p) => {
          p.energy.bmr.formula = 'harris_benedict';
        }),
      ),
    ).toBeTruthy();
  });
});

describe('EngineService', () => {
  it('generates against the active pack and stamps the version', () => {
    const service = new EngineService(PACK_DIR, '1.0.0');
    const out = service.generate({
      userId: 'u-1',
      planDate: '2026-08-24',
      ageYears: 29,
      sexAtBirth: 'male',
      heightCm: 173,
      weightKg: 95,
      goal: 'fat_loss',
      activityLevel: 'moderate',
      conditions: ['none'],
      foodPreference: 'veg',
      foodAllergies: [],
      budgetTier: 'medium',
      lifestyle: 'flexible',
      mealCount: '4',
    });
    expect(out.packVersion).toBe('1.0.0');
    expect(out.targets?.kcal).toBe(2345);
    expect(service.version).toBe('1.0.0');
    expect(service.availableVersions).toContain('1.0.0');
  });

  it('refuses to start when RULE_PACK_VERSION is not on disk', () => {
    expect(() => new EngineService(PACK_DIR, '2.0.0')).toThrow(
      /not found; available/,
    );
  });

  it('refuses to regenerate against an unknown pack version', () => {
    const service = new EngineService(PACK_DIR, '1.0.0');
    expect(() =>
      service.generateWithPack(
        {
          userId: 'u-1',
          planDate: '2026-08-24',
          ageYears: 29,
          sexAtBirth: 'male',
          heightCm: 173,
          weightKg: 95,
          goal: 'fat_loss',
          activityLevel: 'moderate',
          conditions: ['none'],
          foodPreference: 'veg',
          foodAllergies: [],
          budgetTier: 'medium',
          lifestyle: 'flexible',
          mealCount: '4',
        },
        '3.0.0',
      ),
    ).toThrow(/unknown rule pack version/);
  });
});
