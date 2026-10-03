import { AdminReportsController } from '../src/admin/admin-reports.controller';
import { toCsv } from '../src/admin/admin-reports.service';
import { UserAccessService } from '../src/users/user-access.service';

/// Admin panel plan, Phase D: reports, CSV, and the activity that analytics count.

describe('toCsv', () => {
  it('should quote every field and double quotes inside one', () => {
    const csv = toCsv({
      kind: 'offers',
      from: '',
      to: '',
      columns: ['code', 'note'],
      rows: [['DIWALI', 'say "hi", then go']],
    });
    expect(csv).toBe('"code","note"\r\n"DIWALI","say ""hi"", then go"\r\n');
  });
});

describe('active days', () => {
  it('should write one row per person per Indian day, however often the app refreshes', async () => {
    const inserted: { userId: number; day: string }[] = [];
    const activity = {
      createQueryBuilder: () => {
        let row: { userId: number; day: string };
        const qb = {
          insert: () => qb,
          values: (v: { userId: number; day: string }) => ((row = v), qb),
          orIgnore: () => qb,
          execute: () => (inserted.push(row), Promise.resolve()),
        };
        return qb;
      },
    };
    const access = new UserAccessService(
      {} as never,
      {} as never,
      activity as never,
    );

    // 20:00 UTC on the 4th is already the 5th in India.
    await access.recordActive(7, new Date('2026-10-04T20:00:00Z'));
    await access.recordActive(7, new Date('2026-10-04T21:00:00Z'));
    await access.recordActive(7, new Date('2026-10-05T19:00:00Z'));
    expect(inserted).toEqual([
      { userId: 7, day: '2026-10-05' },
      { userId: 7, day: '2026-10-06' },
    ]);
  });
});

describe('AdminReportsController', () => {
  const report = {
    kind: 'payments' as const,
    from: '2026-10-01T00:00:00.000Z',
    to: '2026-10-05T00:00:00.000Z',
    columns: ['day', 'paid_orders'],
    rows: [['2026-10-01', 3]],
  };

  function setup() {
    const audits: Record<string, unknown>[] = [];
    const headers: Record<string, string> = {};
    const controller = new AdminReportsController(
      { report: () => Promise.resolve(report) } as never,
      {
        record: (r: Record<string, unknown>) => (
          audits.push(r),
          Promise.resolve()
        ),
      } as never,
    );
    const res = {
      set: (h: Record<string, string>) => Object.assign(headers, h),
    };
    return { controller, audits, headers, res };
  }
  const request = { user: { id: 1, role: { id: 9 } } } as never;

  it('should answer JSON without an audit row', async () => {
    const { controller, audits } = setup();
    const out = await controller.report(
      'payments',
      { from: report.from, to: report.to },
      request,
      '1.1.1.1',
      {} as never,
    );
    expect(out).toEqual(report);
    expect(audits).toEqual([]);
  });

  it('should send a CSV file and record the export', async () => {
    const { controller, audits, headers, res } = setup();
    const out = await controller.report(
      'payments',
      { from: report.from, to: report.to, format: 'csv' },
      request,
      '1.1.1.1',
      res as never,
    );
    expect(out).toBe('"day","paid_orders"\r\n"2026-10-01","3"\r\n');
    expect(headers['Content-Type']).toContain('text/csv');
    expect(headers['Content-Disposition']).toContain(
      'eatzify-payments-2026-10-01-to-2026-10-05.csv',
    );
    expect(audits).toEqual([
      expect.objectContaining({
        action: 'export',
        resource: 'report/payments',
        meta: expect.objectContaining({ rows: 1 }),
      }),
    ]);
  });
});
