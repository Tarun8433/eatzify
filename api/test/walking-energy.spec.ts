import {
  kcalPer1000Steps,
  measuredStride,
} from '../src/measurements/walking-energy';
import { MeasurementsService } from '../src/measurements/measurements.service';

/// D-256. Worked by hand: 70 kg, 0.7 m stride → 700 m at 80 m/min = 8.75 min;
/// VO2 = 0.1 × 80 + 3.5 = 11.5 → MET 3.286; 3.286 × 3.5 × 70 / 200 × 8.75 = 35.2 kcal.
describe('calories per 1,000 steps', () => {
  const walked = [{ steps: 10000, distanceM: 7000 }];

  it('should follow the ACSM equation from the person’s own stride', () => {
    expect(
      kcalPer1000Steps({ weightKg: 70, heightCm: 170, days: walked }),
    ).toEqual({ kcal: 35, is_estimated: true, stride_from: 'distance' });
  });

  it('should scale with weight rather than use one fixed figure', () => {
    expect(
      kcalPer1000Steps({ weightKg: 100, heightCm: 170, days: walked })?.kcal,
    ).toBe(50);
  });

  it('should fall back to height when no distance was measured', () => {
    expect(kcalPer1000Steps({ weightKg: 70, heightCm: 170, days: [] })).toEqual(
      { kcal: 35, is_estimated: true, stride_from: 'height' },
    );
  });

  it('should say nothing without a weight', () => {
    expect(
      kcalPer1000Steps({ weightKg: null, heightCm: 170, days: walked }),
    ).toBeNull();
  });

  it('should say nothing with neither a stride nor a height', () => {
    expect(
      kcalPer1000Steps({ weightKg: 70, heightCm: null, days: [] }),
    ).toBeNull();
  });
});

describe('measured stride', () => {
  it('should ignore days too short to say anything', () => {
    expect(measuredStride([{ steps: 400, distanceM: 300 }])).toBeNull();
  });

  it('should refuse a "stride" that is really a bike ride', () => {
    expect(measuredStride([{ steps: 3000, distanceM: 20000 }])).toBeNull();
  });

  it('should weight each day by its steps', () => {
    expect(
      measuredStride([
        { steps: 9000, distanceM: 6300 },
        { steps: 1000, distanceM: 800 },
      ]),
    ).toBeCloseTo(0.71);
  });
});

describe('GET /measurements/steps', () => {
  const row = (kind: string, diaryDate: string, value: number) => ({
    id: `${kind}-${diaryDate}`,
    userId: 1,
    kind,
    diaryDate,
    value: String(value),
    unit: kind === 'steps' ? 'steps' : 'm',
    isSuspect: false,
    source: 'health_connect',
  });

  it('should carry the rate, from device days paired by date and the logged weight', async () => {
    const find = jest
      .fn()
      // The history itself.
      .mockResolvedValueOnce([row('steps', '2026-09-28', 10000)])
      // The stride window: one paired day, one day with steps alone.
      .mockResolvedValueOnce([
        row('steps', '2026-09-28', 10000),
        row('distance_m', '2026-09-28', 7000),
        row('steps', '2026-09-27', 5000),
      ]);
    const service = new MeasurementsService(
      {
        find,
        findOne: () => Promise.resolve(row('weight', '2026-09-28', 100)),
      } as never,
      {
        findOne: () => Promise.resolve({ weightKg: '70.00', heightCm: 150 }),
      } as never,
    );

    const view = await service.history(1, 'steps');

    // 100 kg (the logged weight, not the profile's 70) over a 0.7 m measured stride.
    expect(view.kcal_per_1000_steps).toEqual({
      kcal: 50,
      is_estimated: true,
      stride_from: 'distance',
    });
  });

  it('should not attach it to any other kind', async () => {
    const service = new MeasurementsService(
      { find: () => Promise.resolve([]) } as never,
      {} as never,
    );

    expect(await service.history(1, 'weight')).not.toHaveProperty(
      'kcal_per_1000_steps',
    );
  });
});
