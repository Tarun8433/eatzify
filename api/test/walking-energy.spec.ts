import {
  burnedByDay,
  dayEnergy,
  kcalPer1000Steps,
  measuredStride,
  type ActivityDay,
} from '../src/measurements/walking-energy';
import { MeasurementsService } from '../src/measurements/measurements.service';

/// D-268. Worked by hand for 70 kg, 10,000 steps over 7,000 m (a 0.7 m stride):
///   flat, default 80 m/min → 87.5 min; VO2 = 3.5 + 8 = 11.5
///   gross  = 11.5 × 70 / 200 × 87.5 = 352.2 kcal; active = 8 × 70 / 200 × 87.5 = 245 kcal
const day = (over: Partial<ActivityDay> = {}): ActivityDay => ({
  steps: 10000,
  deviceSteps: 10000,
  distanceM: 7000,
  speedMPerMin: null,
  elevationGainM: null,
  floors: null,
  reportedKcal: null,
  ...over,
});
const usual = { m: 0.7, from: 'distance' as const };

describe('one day of walking', () => {
  it('should follow the flat ACSM equation at the default pace, marked estimated', () => {
    expect(dayEnergy(day(), 70, usual)).toEqual({
      gross_kcal: 352,
      active_kcal: 245,
      is_estimated: true,
      stride_from: 'distance',
      speed_from: 'default',
    });
  });

  it('should use the measured walking speed and then not be estimated', () => {
    // 100 m/min → 70 min; VO2 = 13.5 → 13.5 × 0.35 × 70 = 330.75.
    const e = dayEnergy(day({ speedMPerMin: 100 }), 70, usual);
    expect(e.gross_kcal).toBe(331);
    expect(e.is_estimated).toBe(false);
  });

  it('should price an incline from elevation gained over the distance', () => {
    // 140 m over 7,000 m = 2 % → VO2 = 11.5 + 1.8 × 80 × 0.02 = 14.38 → 14.38 × 0.35 × 87.5.
    expect(dayEnergy(day({ elevationGainM: 140 }), 70, usual).gross_kcal).toBe(
      440,
    );
  });

  it('should price stairs on their own and not as an incline', () => {
    // 10 floors = 30 m, all of the elevation → flat walk + 1.8 × 30 × 0.35 = 18.9 kcal.
    const e = dayEnergy(day({ floors: 10, elevationGainM: 30 }), 70, usual);
    expect(e.gross_kcal).toBe(371);
    expect(e.active_kcal).toBe(264);
  });

  it('should cap a grade that is a climb rather than a walk', () => {
    const steep = dayEnergy(day({ elevationGainM: 5000 }), 70, usual);
    const capped = dayEnergy(day({ elevationGainM: 1400 }), 70, usual);
    expect(steep.gross_kcal).toBe(capped.gross_kcal);
  });

  it('should ignore a "walking speed" that is really a bike ride', () => {
    const e = dayEnergy(day({ speedMPerMin: 300 }), 70, usual);
    expect(e.gross_kcal).toBe(352);
    expect(e.speed_from).toBe('default');
  });
});

describe('calories per 1,000 steps', () => {
  const rows = [
    {
      kind: 'steps',
      value: '10000',
      diaryDate: '2026-09-28',
      source: 'health_connect',
    },
    {
      kind: 'distance_m',
      value: '7000',
      diaryDate: '2026-09-28',
      source: 'health_connect',
    },
  ];

  it('should be activity calories ÷ activity steps × 1,000', () => {
    expect(kcalPer1000Steps(rows, { weightKg: 70, heightCm: 170 })).toEqual({
      kcal: 35,
      active_kcal: 25,
      is_estimated: true,
      stride_from: 'distance',
      speed_from: 'default',
    });
  });

  it('should scale with weight rather than use one fixed figure', () => {
    expect(kcalPer1000Steps(rows, { weightKg: 100, heightCm: 170 })?.kcal).toBe(
      50,
    );
  });

  it('should fall back to height when no distance was measured', () => {
    // 0.414 × 1.7 m = 0.7038 m → 703.8 m at 80 m/min.
    expect(kcalPer1000Steps([], { weightKg: 70, heightCm: 170 })).toMatchObject(
      {
        kcal: 35,
        stride_from: 'height',
        is_estimated: true,
      },
    );
  });

  it('should say nothing without a weight, or with neither a stride nor a height', () => {
    expect(
      kcalPer1000Steps(rows, { weightKg: null, heightCm: 170 }),
    ).toBeNull();
    expect(kcalPer1000Steps([], { weightKg: 70, heightCm: null })).toBeNull();
  });
});

describe('calories burned by day', () => {
  const body = { weightKg: 70, heightCm: 170 };
  const row = (
    kind: string,
    value: number,
    diaryDate = '2026-09-28',
    source = 'health_connect',
  ) => ({
    kind,
    value: String(value),
    diaryDate,
    source,
  });

  it("should never use the phone's own figure on a day with steps", () => {
    const burned = burnedByDay(
      [
        row('steps', 10000),
        row('distance_m', 7000),
        row('energy_burned_kcal', 875),
      ],
      body,
    );
    expect(burned.get('2026-09-28')).toBe(245);
  });

  it('should count what the person added to the steps', () => {
    const burned = burnedByDay(
      [
        row('steps', 9000),
        row('distance_m', 6300),
        row('steps_added', 1000, '2026-09-28', 'manual'),
      ],
      body,
    );
    expect(burned.get('2026-09-28')).toBe(245);
  });

  it('should keep a reported figure on a day with no steps', () => {
    expect(
      burnedByDay(
        [row('energy_burned_kcal', 200, '2026-09-27', 'manual')],
        body,
      ).get('2026-09-27'),
    ).toBe(200);
  });

  it('should keep only reported figures without a weight', () => {
    const burned = burnedByDay(
      [row('steps', 10000), row('energy_burned_kcal', 875)],
      {
        weightKg: null,
        heightCm: 170,
      },
    );
    expect(burned.get('2026-09-28')).toBe(875);
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

describe('MeasurementsService', () => {
  const entity = (kind: string, diaryDate: string, value: number) => ({
    id: `${kind}-${diaryDate}`,
    userId: 1,
    kind,
    diaryDate,
    value: String(value),
    unit: 'x',
    isSuspect: false,
    source: 'health_connect',
  });
  const activity = [
    entity('steps', '2026-09-28', 10000),
    entity('distance_m', '2026-09-28', 7000),
    entity('energy_burned_kcal', '2026-09-28', 875),
  ];
  const service = (find: jest.Mock) =>
    new MeasurementsService(
      {
        find,
        findOne: () => Promise.resolve(entity('weight', '2026-09-28', 100)),
      } as never,
      {
        findOne: () => Promise.resolve({ weightKg: '70.00', heightCm: 150 }),
      } as never,
    );

  it('should carry the rate on the steps history, from the logged weight', async () => {
    const find = jest
      .fn()
      .mockResolvedValueOnce([entity('steps', '2026-09-28', 10000)])
      .mockResolvedValueOnce(activity);

    const view = await service(find).history(1, 'steps');

    // 100 kg (the logged weight, not the profile's 70) over a 0.7 m measured stride.
    expect(view.kcal_per_1000_steps).toMatchObject({
      kcal: 50,
      stride_from: 'distance',
    });
  });

  it("should chart calories burned as worked out, not the phone's figure", async () => {
    const view = await service(jest.fn().mockResolvedValue(activity)).history(
      1,
      'energy_burned_kcal',
    );

    // 100 kg: 8 × 100 / 200 × 87.5 = 350.
    expect(view.points).toEqual([
      expect.objectContaining({
        diary_date: '2026-09-28',
        value: 350,
        id: 'steps-2026-09-28',
      }),
    ]);
  });

  it('should not attach the rate to any other kind', async () => {
    const plain = new MeasurementsService(
      { find: () => Promise.resolve([]) } as never,
      {} as never,
    );
    expect(await plain.history(1, 'weight')).not.toHaveProperty(
      'kcal_per_1000_steps',
    );
  });
});
