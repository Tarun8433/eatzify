import { LogsService } from '../src/logs/logs.service';

/// D-136. A food_log row copies kcal and three macros at log time; fibre was the fourth number the
/// engine targets and the one the diary never recorded. These run the real day() reducer against
/// stubbed repositories — the arithmetic and the null rule are the service's, not a mock's.

const foodRow = (over: Record<string, unknown>) => ({
  id: 'r1',
  slot: 'lunch',
  customName: null,
  food: { name: 'Dal' },
  quantityG: '150.0',
  measureLabel: '1 katori',
  kcal: '174.0',
  proteinG: '10.2',
  carbG: '24.0',
  fatG: '4.1',
  fibreG: '6.3',
  source: 'manual',
  loggedAt: new Date('2026-09-01T08:00:00Z'),
  ...over,
});

const serviceWith = (rows: unknown[], targets: Record<string, number> | null) =>
  new LogsService(
    { find: () => Promise.resolve(rows) } as never,
    {} as never,
    {
      findOne: () => Promise.resolve(targets === null ? null : { targets }),
    } as never,
    { find: () => Promise.resolve([]) } as never,
  );

describe('fibre in the diary day (D-136)', () => {
  it('should sum fibre into the day totals', async () => {
    const service = serviceWith(
      [foodRow({}), foodRow({ id: 'r2', fibreG: '2.2' })],
      null,
    );

    const day = await service.day(7, '2026-09-01');

    expect(day.totals.fibre_g).toBe(Math.round(6.3 + 2.2));
  });

  it('should treat an unrecorded fibre as nothing, not as nought', async () => {
    // A custom entry (fibreG null) must not block the sum, and the ENTRY must say null so a
    // client can tell "not recorded" from "zero fibre".
    const service = serviceWith(
      [foodRow({}), foodRow({ id: 'r2', fibreG: null })],
      null,
    );

    const day = await service.day(7, '2026-09-01');

    expect(day.totals.fibre_g).toBe(6);
    expect(day.entries[1].fibre_g).toBeNull();
  });

  it('should surface the fibre target the plan has always carried', async () => {
    // The engine computes targets.fibreG and the plan stores it; the day view just never mapped
    // it. This is the line that makes "25 / 30 g" possible.
    const service = serviceWith([], {
      kcal: 1500,
      proteinG: 99,
      carbG: 183,
      fatG: 42,
      fibreG: 30,
    });

    const day = await service.day(7, '2026-09-01');

    expect(day.targets?.fibre_g).toBe(30);
    expect(day.totals.fibre_g).toBe(0);
  });
});
