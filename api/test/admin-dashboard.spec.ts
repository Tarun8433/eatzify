import {
  AdminDashboardService,
  istDayStart,
} from '../src/admin/admin-dashboard.service';

describe('admin dashboard', () => {
  it('should start "today" at midnight in India, not UTC', () => {
    // 2026-10-03 20:00 UTC is already 4 October 01:30 in India.
    expect(istDayStart(new Date('2026-10-03T20:00:00Z')).toISOString()).toBe(
      '2026-10-03T18:30:00.000Z',
    );
    expect(istDayStart(new Date('2026-10-03T10:00:00Z')).toISOString()).toBe(
      '2026-10-02T18:30:00.000Z',
    );
  });

  it('should zero-fill every day of the range so a chart has no gaps', async () => {
    const service = new AdminDashboardService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );
    // `raw` is the SQL; this checks the zero-filling around it.
    (service as unknown as { raw: () => Promise<unknown> }).raw = () =>
      Promise.resolve([{ day: '2026-10-02', n: '3', sum: '149700' }]);

    const points = await service.series(
      'payments_paid',
      new Date('2026-10-01T06:00:00Z'),
      new Date('2026-10-03T06:00:00Z'),
    );

    expect(points).toEqual([
      { day: '2026-10-01', count: 0, amount_paise: '0' },
      { day: '2026-10-02', count: 3, amount_paise: '149700' },
      { day: '2026-10-03', count: 0, amount_paise: '0' },
    ]);
  });
});
