import { type Repository } from 'typeorm';
import { CheckInEntity } from '../src/coach/entities/check-in.entity';
import { CheckInsService } from '../src/coach/check-ins.service';
import { CoachClientsService } from '../src/coach/coach-clients.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import type { RosterRow } from '../src/coach/client-view.serializer';
import {
  NO_LOG_ALERT_DAYS,
  alertsFor,
  byRisk,
  daysBetweenDates,
  isOverdue,
  weekOf,
} from '../src/coach/check-in-rules';

/// docs/02 FR-5.2 and FR-5.3: the weekly review queue, and the four signals beside it.

/// A Thursday, 10:00 IST — inside the diary day that begins at 04:00.
const NOW = new Date('2026-09-17T06:00:00Z');
const THIS_MONDAY = '2026-09-14';

type Row = Partial<CheckInEntity>;

const client = (over: Partial<RosterRow> = {}): RosterRow => ({
  client_user_id: 7,
  name: 'A. Client',
  scopes: ['progress'],
  expires_at: '2027-01-01T00:00:00.000Z',
  days_since_last_log: 1,
  adherence_pct: 80,
  goal: 'fat_loss',
  weight_change_30d: -1.2,
  ...over,
});

function serviceWith({
  rows = [],
  roster = [client()],
  subscriptions = [],
}: {
  rows?: Row[];
  roster?: RosterRow[];
  subscriptions?: Partial<SubscriptionEntity>[];
} = {}) {
  const sent: { kind: string; userId: number }[] = [];
  const audits: string[] = [];

  const matches = (
    row: Record<string, unknown>,
    where: Record<string, unknown>,
  ) =>
    Object.entries(where).every(([key, want]) => {
      const have = row[key];
      if (want && typeof want === 'object' && '_value' in (want as object)) {
        return ((want as { _value: unknown[] })._value ?? []).includes(have);
      }
      return have === want;
    });

  const checkIns = {
    rows,
    create: (row: Row) => row,
    save: (row: Row) => {
      const at = rows.findIndex((r) => r.id && r.id === row.id);
      const saved = { id: row.id ?? `c${rows.length + 1}`, ...row };
      if (at >= 0) rows[at] = saved;
      else rows.push(saved);
      return Promise.resolve(saved);
    },
    find: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(rows.filter((r) => matches(r as never, where))),
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(rows.find((r) => matches(r as never, where)) ?? null),
  } as unknown as Repository<CheckInEntity>;

  const subs = {
    find: () => Promise.resolve(subscriptions),
  } as unknown as Repository<SubscriptionEntity>;

  const clients = {
    roster: (_: number, __: Date, resource = 'coach/clients') => {
      audits.push(resource);
      return Promise.resolve(roster);
    },
  } as unknown as CoachClientsService;

  const notifications = {
    notify: (input: { kind: string; userId: number }) => {
      sent.push(input);
      return Promise.resolve({ id: 'n1' });
    },
  } as unknown as NotificationsService;

  return {
    service: new CheckInsService(checkIns, subs, clients, notifications),
    rows,
    sent,
    audits,
  };
}

describe('when a check-in falls due', () => {
  it('should belong to the Monday of its week, whatever day it is read on', () => {
    expect(weekOf('2026-09-17')).toBe(THIS_MONDAY);
    expect(weekOf('2026-09-14')).toBe(THIS_MONDAY);
    expect(weekOf('2026-09-20')).toBe(THIS_MONDAY);
    expect(weekOf('2026-09-21')).toBe('2026-09-21');
  });

  it('should count a week that has gone by as overdue', () => {
    expect(isOverdue('2026-09-07', THIS_MONDAY)).toBe(true);
    expect(isOverdue(THIS_MONDAY, THIS_MONDAY)).toBe(false);
    expect(daysBetweenDates('2026-09-07', THIS_MONDAY)).toBe(7);
  });
});

describe('the queue (docs/02 FR-5.2)', () => {
  it('should open this week’s review the first time the tab is read', async () => {
    const { service, rows } = serviceWith();

    const queue = await service.queue(1, NOW);

    expect(rows).toHaveLength(1);
    expect(queue[0]).toMatchObject({
      client_user_id: 7,
      name: 'A. Client',
      due_on: THIS_MONDAY,
      status: 'due',
      days_since_last_log: 1,
    });
  });

  it('should not open a second one for the same week', async () => {
    const { service, rows } = serviceWith({
      rows: [
        {
          id: 'c1',
          coachUserId: 1,
          clientUserId: 7,
          dueOn: THIS_MONDAY,
          status: 'due',
        },
      ],
    });

    await service.queue(1, NOW);

    expect(rows).toHaveLength(1);
  });

  it('should mark last week’s unanswered review as missed', async () => {
    const { service, rows } = serviceWith({
      rows: [
        {
          id: 'c1',
          coachUserId: 1,
          clientUserId: 7,
          dueOn: '2026-09-07',
          status: 'due',
        },
      ],
    });

    await service.queue(1, NOW);

    expect(rows.find((r) => r.id === 'c1')?.status).toBe('missed');
  });

  it('should put what was missed first, then the oldest (docs/02 FR-5.2 "sorted by risk")', () => {
    const sorted = byRisk([
      { status: 'due', due_on: '2026-09-14', days_since_last_log: 0 },
      { status: 'missed', due_on: '2026-09-07', days_since_last_log: 9 },
      { status: 'due', due_on: '2026-09-07', days_since_last_log: 4 },
    ]);

    expect(sorted.map((s) => `${s.status}:${s.due_on}`)).toEqual([
      'missed:2026-09-07',
      'due:2026-09-07',
      'due:2026-09-14',
    ]);
  });

  it('should show only what was asked for', async () => {
    const { service } = serviceWith({
      rows: [
        {
          id: 'c1',
          coachUserId: 1,
          clientUserId: 7,
          dueOn: THIS_MONDAY,
          status: 'completed',
        },
      ],
    });

    expect(await service.queue(1, NOW, 'due')).toHaveLength(0);
    expect(await service.queue(1, NOW, 'completed')).toHaveLength(1);
  });

  it('should be empty for a coach nobody has granted anything to', async () => {
    const { service, rows } = serviceWith({ roster: [] });

    expect(await service.queue(1, NOW)).toEqual([]);
    expect(rows).toHaveLength(0);
  });

  /// docs/10 §6: a read that carries health-derived figures is audited, under its own name.
  it('should record the read as the check-in screen, not as the client list', async () => {
    const { service, audits } = serviceWith();

    await service.queue(1, NOW);

    expect(audits).toEqual(['coach/checkins']);
  });
});

describe('completing one (docs/09 §6)', () => {
  const open: Row = {
    id: 'c1',
    coachUserId: 1,
    clientUserId: 7,
    dueOn: THIS_MONDAY,
    status: 'due',
  };

  it('should keep the note and what they agreed to do', async () => {
    const { service, rows } = serviceWith({ rows: [{ ...open }] });

    const view = await service.complete(
      1,
      'c1',
      {
        notes: ' Eating well, sleep is the problem ',
        actions: ['Walk after dinner', ' '],
      },
      NOW,
    );

    expect(view).toMatchObject({
      status: 'completed',
      notes: 'Eating well, sleep is the problem',
    });
    expect(view.actions).toEqual(['Walk after dinner']);
    expect(rows[0].completedAt).toBe(NOW);
  });

  it('should tell the client it happened, without saying how they are doing', async () => {
    const { service, sent } = serviceWith({ rows: [{ ...open }] });

    await service.complete(
      1,
      'c1',
      { actions: ['Add a protein at lunch'] },
      NOW,
    );

    expect(sent[0]).toMatchObject({ userId: 7, kind: 'checkin_completed' });
  });

  it('should refuse a note nobody would read', async () => {
    const { service } = serviceWith({ rows: [{ ...open }] });

    await expect(
      service.complete(1, 'c1', { notes: 'x'.repeat(2001) }, NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'CHECK_IN_TOO_LONG' } },
    });
  });

  it('should refuse another coach’s review', async () => {
    const { service } = serviceWith({ rows: [{ ...open }] });

    await expect(service.complete(99, 'c1', {}, NOW)).rejects.toMatchObject({
      status: 404,
    });
  });
});

describe('alerts (docs/02 FR-5.3)', () => {
  it('should name the four signals', () => {
    expect(
      alertsFor({
        daysSinceLastLog: NO_LOG_ALERT_DAYS,
        goal: 'fat_loss',
        weightChange30d: 0.8,
        planEndsInDays: 12,
        missedCheckIn: true,
      }),
    ).toEqual(['no_logs', 'off_trend', 'plan_expiring', 'checkin_missed']);
  });

  it('should say nothing about somebody who is fine', () => {
    expect(
      alertsFor({
        daysSinceLastLog: 1,
        goal: 'fat_loss',
        weightChange30d: -1.1,
        planEndsInDays: 200,
        missedCheckIn: false,
      }),
    ).toEqual([]);
  });

  /// A null is not a signal: "no weight reading" is not "off trend", and a grant that hides weight
  /// simply produces no weight alert (docs/10).
  it('should never read a missing figure as a problem', () => {
    expect(
      alertsFor({
        daysSinceLastLog: null,
        goal: null,
        weightChange30d: null,
        planEndsInDays: null,
        missedCheckIn: false,
      }),
    ).toEqual([]);
  });

  it('should call gaining weight off-trend only for somebody trying to lose it', () => {
    const gaining = {
      daysSinceLastLog: 0,
      weightChange30d: 1.5,
      planEndsInDays: null,
    };
    expect(
      alertsFor({ ...gaining, goal: 'fat_loss', missedCheckIn: false }),
    ).toEqual(['off_trend']);
    expect(
      alertsFor({ ...gaining, goal: 'muscle_gain', missedCheckIn: false }),
    ).toEqual([]);
  });

  it('should list a client once, with everything that is true about them', async () => {
    const { service } = serviceWith({
      roster: [client({ days_since_last_log: 6, weight_change_30d: 0.4 })],
      rows: [
        {
          id: 'c1',
          coachUserId: 1,
          clientUserId: 7,
          dueOn: '2026-09-07',
          status: 'missed',
        },
      ],
      subscriptions: [
        {
          userId: 7,
          status: 'active',
          currentPeriodEnd: new Date('2026-09-30T00:00:00Z'),
        },
      ],
    });

    const alerts = await service.alerts(1, NOW);

    expect(alerts).toHaveLength(1);
    expect(alerts[0].kinds).toEqual([
      'no_logs',
      'off_trend',
      'plan_expiring',
      'checkin_missed',
    ]);
    expect(alerts[0].plan_ends_in_days).toBe(13);
  });

  it('should leave out anybody with nothing to report', async () => {
    const { service } = serviceWith();

    expect(await service.alerts(1, NOW)).toEqual([]);
  });
});
