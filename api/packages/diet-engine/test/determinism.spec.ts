/** docs/16 §2 GV-08 and GV-09 — determinism and rule-pack isolation. */
import { createPrng, generatePlan, hashSeed } from '../src';
import { input, loadPack } from './helpers';

const pack = loadPack();
const gv01 = input({
  sexAtBirth: 'male', ageYears: 29, heightCm: 173, weightKg: 95.0,
  activityLevel: 'moderate', goal: 'fat_loss', foodPreference: 'veg', mealCount: '4',
});

describe('GV-08 — determinism', () => {
  it('produces byte-identical JSON across 1000 runs', () => {
    const first = JSON.stringify(generatePlan(gv01, pack));
    for (let i = 0; i < 1000; i += 1) {
      expect(JSON.stringify(generatePlan(gv01, pack))).toBe(first);
    }
  });

  it('keeps targets identical for a different user_id', () => {
    const a = generatePlan(gv01, pack);
    const b = generatePlan({ ...gv01, userId: 'u-test-9999' }, pack);
    expect(b.targets).toEqual(a.targets);
    expect(b.derived).toEqual(a.derived);
  });

  it('seeds the prng from user_id + plan_date + pack version', () => {
    const a = hashSeed('u-1', '2026-08-24', '1.0.0');
    expect(hashSeed('u-1', '2026-08-24', '1.0.0')).toBe(a);
    expect(hashSeed('u-2', '2026-08-24', '1.0.0')).not.toBe(a);
    expect(hashSeed('u-1', '2026-08-25', '1.0.0')).not.toBe(a);
    expect(hashSeed('u-1', '2026-08-24', '1.1.0')).not.toBe(a);
  });

  it('yields a repeatable prng stream for a given seed', () => {
    const draw = (): number[] => {
      const next = createPrng(hashSeed('u-1', '2026-08-24', '1.0.0'));
      return [next(), next(), next()];
    };
    expect(draw()).toEqual(draw());
    for (const v of draw()) {
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);
    }
  });

  it('uses no clock and no global random', () => {
    const fs = require('node:fs') as typeof import('node:fs');
    const dir = `${__dirname}/../src`;
    const stripComments = (src: string): string =>
      src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
    const code = fs
      .readdirSync(dir)
      .filter((f) => f.endsWith('.ts'))
      .map((f) => stripComments(fs.readFileSync(`${dir}/${f}`, 'utf8')))
      .join('\n');
    expect(code).not.toMatch(/Date\.now|new Date\(|Math\.random/);
  });
});

describe('GV-09 — rule pack isolation', () => {
  it('reflects a changed constant in the new pack only', () => {
    const v1 = generatePlan(gv01, pack);
    const v11 = {
      ...pack,
      version: '1.1.0',
      macros: { ...pack.macros, fat: { ...pack.macros.fat, pct_default: 0.30 } },
    };
    const out11 = generatePlan(gv01, v11);

    expect(out11.packVersion).toBe('1.1.0');
    expect(out11.targets?.fatG).toBeGreaterThan(v1.targets?.fatG ?? 0);
    // Re-reading under the original pack is unchanged — snapshot integrity.
    expect(JSON.stringify(generatePlan(gv01, pack))).toBe(JSON.stringify(v1));
  });

  it('stamps every output with the pack version it was built from', () => {
    expect(generatePlan(gv01, pack).packVersion).toBe('1.0.0');
  });
});

describe('safety invariants hold across a swept profile set (docs/16 §4)', () => {
  const sexes = ['male', 'female'] as const;
  const activities = ['sedentary', 'light', 'moderate', 'heavy'] as const;
  const goals = ['fat_loss', 'muscle_gain', 'maintenance'] as const;

  it('never emits a target below the floor, below BMR, or below the carb floor', () => {
    let planned = 0;
    for (const sexAtBirth of sexes) {
      for (const activityLevel of activities) {
        for (const goal of goals) {
          for (let weightKg = 40; weightKg <= 140; weightKg += 10) {
            for (let ageYears = 18; ageYears <= 80; ageYears += 8) {
              const out = generatePlan(
                input({ sexAtBirth, activityLevel, goal, weightKg, ageYears, heightCm: 165 }),
                pack,
              );
              if (out.targets === null) continue;
              planned += 1;
              const floor = sexAtBirth === 'female' ? 1200 : 1500;
              expect(out.targets.kcal).toBeGreaterThanOrEqual(floor);
              expect(out.targets.kcal).toBeGreaterThanOrEqual(out.derived?.bmr ?? 0);
              expect(out.targets.carbG).toBeGreaterThanOrEqual(100);
              expect(out.targets.proteinG).toBeGreaterThanOrEqual(0.83 * weightKg - 1);
              expect(out.targets.proteinG).toBeLessThanOrEqual(2.2 * (out.derived?.abw ?? 0) + 1);
            }
          }
        }
      }
    }
    expect(planned).toBeGreaterThan(400);
  });
});
