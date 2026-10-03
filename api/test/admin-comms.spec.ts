import { AdminCampaignsService } from '../src/admin/admin-campaigns.service';
import { AdminAlertsService } from '../src/admin/admin-alerts.service';
import { AdminAudienceService } from '../src/admin/admin-audience.service';
import { AnnouncementsService } from '../src/campaigns/announcements.service';
import { CouponsService } from '../src/billing/coupons.service';
import { RoleEnum } from '../src/roles/roles.enum';

/// Admin panel plan, Phase C: messages, the bell, announcements and offer rules.

const NOW = new Date('2026-10-05T10:00:00Z');
const ADMIN = { userId: 1, roleId: RoleEnum.admin };

type Row = Record<string, unknown> & { id: string; status: string };

function campaigns(audienceIds: number[], pushConfigured = false) {
  const rows: Row[] = [];
  const sentTo: number[] = [];
  const pushed: number[][] = [];
  const audits: string[] = [];
  const repo = {
    create: (r: Record<string, unknown>) => ({
      status: 'scheduled',
      results: {},
      createdAt: NOW,
      ...r,
    }),
    save: (r: Row) => {
      if (!r.id) {
        r.id = `c${rows.length + 1}`;
        rows.push(r);
      }
      return Promise.resolve(r);
    },
    update: (where: { id: string; status: string }, patch: Partial<Row>) => {
      const r = rows.find(
        (x) => x.id === where.id && x.status === where.status,
      );
      if (r) Object.assign(r, patch);
      return Promise.resolve({ affected: r ? 1 : 0 });
    },
    find: () => Promise.resolve(rows.filter((r) => r.status === 'scheduled')),
    findOne: ({ where }: { where: { id: string } }) =>
      Promise.resolve(rows.find((r) => r.id === where.id) ?? null),
  };
  const service = new AdminCampaignsService(
    repo as never,
    { createQueryBuilder: () => ({ select: () => ({}) }) } as never,
    { count: () => Promise.resolve(audienceIds.length) } as never,
    { idsFor: () => Promise.resolve(audienceIds) } as never,
    {
      notify: (n: { userId: number }) => (
        sentTo.push(n.userId),
        Promise.resolve({})
      ),
    } as never,
    {
      configured: pushConfigured,
      sendToUsers: (ids: number[]) => (
        pushed.push(ids),
        Promise.resolve({ sent: ids.length, failed: 0 })
      ),
    } as never,
    {
      record: (r: { action: string }) => (
        audits.push(r.action),
        Promise.resolve()
      ),
    } as never,
  );
  // The read-count query needs a database; this checks sending, not reporting.
  (service as unknown as { views: (r: Row[]) => Promise<Row[]> }).views = (r) =>
    Promise.resolve(r);
  return { service, rows, sentTo, pushed, audits };
}

const message = {
  title: 'Diwali hours',
  body: 'Support answers until 6 pm today.',
  content_class: 'service' as const,
  segment: {},
};

describe('campaigns', () => {
  it('should refuse a channel that is not set up', async () => {
    const { service } = campaigns([1, 2]);
    await expect(
      service.create({ ...message, channels: ['sms'] }, ADMIN, NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'CHANNEL_NOT_CONFIGURED' } },
    });
    expect(service.channels()).toMatchObject({
      in_app: true,
      push: false,
      sms: false,
      whatsapp: false,
    });
  });

  it('should send now to everyone in the audience, in the app and by push, and audit it', async () => {
    const { service, rows, sentTo, pushed, audits } = campaigns(
      [4, 5, 6],
      true,
    );
    await service.create({ ...message, channels: ['push'] }, ADMIN, NOW);

    expect(sentTo).toEqual([4, 5, 6]);
    expect(pushed).toEqual([[4, 5, 6]]);
    expect(rows[0]).toMatchObject({
      status: 'sent',
      audience: 3,
      channels: ['in_app', 'push'],
      results: { in_app: { sent: 3, failed: 0 }, push: { sent: 3, failed: 0 } },
    });
    expect(audits).toEqual(['notification_send']);
  });

  it('should hold a scheduled message until it is due, then send it once', async () => {
    const { service, rows, sentTo } = campaigns([4]);
    const later = new Date(NOW.getTime() + 3_600_000);
    await service.create(
      { ...message, channels: ['in_app'], scheduled_at: later.toISOString() },
      ADMIN,
      NOW,
    );
    expect(rows[0].status).toBe('scheduled');
    expect(sentTo).toEqual([]);

    await service.runDue(later);
    await service.runDue(later);
    expect(sentTo).toEqual([4]);
    expect(rows[0].status).toBe('sent');
  });

  it('should refuse a time in the past and cancel only what is still scheduled', async () => {
    const { service, rows } = campaigns([4]);
    await expect(
      service.create(
        {
          ...message,
          channels: ['in_app'],
          scheduled_at: '2026-10-01T00:00:00Z',
        },
        ADMIN,
        NOW,
      ),
    ).rejects.toMatchObject({
      response: { error: { code: 'SCHEDULE_IN_PAST' } },
    });

    const later = new Date(NOW.getTime() + 3_600_000).toISOString();
    await service.create(
      { ...message, channels: ['in_app'], scheduled_at: later },
      ADMIN,
      NOW,
    );
    await service.cancel(rows[0].id, ADMIN);
    expect(rows[0].status).toBe('cancelled');
    await expect(service.cancel(rows[0].id, ADMIN)).rejects.toMatchObject({
      status: 409,
    });
  });
});

describe('audience for a commercial message', () => {
  it('should reach only people whose latest marketing consent is yes', async () => {
    const audience = new AdminAudienceService(
      {
        find: () =>
          Promise.resolve([{ userId: 1 }, { userId: 2 }, { userId: 3 }]),
      } as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {
        find: () =>
          Promise.resolve([
            { userId: 1, granted: true },
            { userId: 2, granted: false },
            { userId: 2, granted: true },
          ]),
      } as never,
    );
    // Newest first: user 2 said no most recently; user 3 never answered.
    expect(await audience.idsFor({}, 'commercial', NOW)).toEqual([1]);
    expect(await audience.idsFor({}, 'service', NOW)).toEqual([1, 2, 3]);
    await expect(
      audience.idsFor({ conditions: ['diabetes'] }, 'commercial', NOW),
    ).rejects.toMatchObject({
      status: 403,
    });
  });
});

describe('the bell', () => {
  it('should show each role only the queues it can act on', async () => {
    const count = (n: number) => ({ count: () => Promise.resolve(n) });
    const alerts = new AdminAlertsService(
      count(2) as never,
      count(1) as never,
      count(3) as never,
      count(0) as never,
      count(9) as never,
    );
    const admin = await alerts.for(RoleEnum.admin, NOW);
    expect(admin.map((a) => a.kind).sort()).toEqual([
      'coach_applications',
      'failed_payments_last_hour',
      'refund_requests',
      'tickets_waiting',
    ]);
    const content = await alerts.for(RoleEnum.content, NOW);
    expect(content).toEqual([]);
    const finance = await alerts.for(RoleEnum.finance, NOW);
    expect(finance.map((a) => a.kind).sort()).toEqual([
      'failed_payments_last_hour',
      'refund_requests',
      'tickets_waiting',
    ]);
  });
});

describe('announcements in the app', () => {
  it('should show what matches the plan, most urgent first', async () => {
    const rows = [
      { id: 'a', priority: 'normal', audience: 'all' },
      { id: 'b', priority: 'critical', audience: 'paid' },
      { id: 'c', priority: 'important', audience: 'free' },
    ].map((r) => ({
      ...r,
      title: r.id,
      body: '',
      imageUrl: null,
      status: 'published',
      startsAt: NOW,
      endsAt: null,
      createdBy: 1,
      updatedAt: NOW,
    }));
    const service = new AnnouncementsService({
      find: () => Promise.resolve(rows),
    } as never);

    expect((await service.activeFor(true, NOW)).map((a) => a.id)).toEqual([
      'b',
      'a',
    ]);
    expect((await service.activeFor(false, NOW)).map((a) => a.id)).toEqual([
      'c',
      'a',
    ]);
  });

  it('should refuse an end before the start', async () => {
    const service = new AnnouncementsService({
      create: (r: unknown) => r,
    } as never);
    await expect(
      service.create(
        {
          title: 'x',
          body: 'y',
          priority: 'normal',
          audience: 'all',
          starts_at: '2026-10-05T10:00:00Z',
          ends_at: '2026-10-04T10:00:00Z',
        },
        1,
        NOW,
      ),
    ).rejects.toMatchObject({
      response: { error: { code: 'ANNOUNCEMENT_WINDOW' } },
    });
  });
});

describe('offer rules at checkout', () => {
  const offer = (over: Record<string, unknown>) => ({
    code: 'WELCOME',
    percentOff: 20,
    maxUses: 10,
    usedCount: 0,
    expiresAt: null,
    active: true,
    startsAt: null,
    eligibility: 'all',
    tier: null,
    ...over,
  });
  const service = (row: Record<string, unknown>, paidBefore = 0) =>
    new CouponsService(
      { findOne: () => Promise.resolve(row) } as never,
      { count: () => Promise.resolve(paidBefore) } as never,
    );
  const buyer = { userId: 5, tier: 'PRO' };

  it('should not work before its start', async () => {
    const early = service(
      offer({ startsAt: new Date('2026-10-06T00:00:00Z') }),
    );
    expect(await early.discountFor('WELCOME', 64_900n, NOW, buyer)).toBeNull();
  });

  it('should work only for its tier', async () => {
    const basicOnly = service(offer({ tier: 'BASIC' }));
    expect(
      await basicOnly.discountFor('WELCOME', 64_900n, NOW, buyer),
    ).toBeNull();
    expect(
      await basicOnly.discountFor('WELCOME', 24_900n, NOW, {
        userId: 5,
        tier: 'BASIC',
      }),
    ).toMatchObject({ discountPaise: 4_980n });
  });

  it('should work for a new user only when they have never paid', async () => {
    expect(
      await service(offer({ eligibility: 'new_users' }), 0).discountFor(
        'WELCOME',
        64_900n,
        NOW,
        buyer,
      ),
    ).toMatchObject({
      discountPaise: 12_980n,
    });
    expect(
      await service(offer({ eligibility: 'new_users' }), 1).discountFor(
        'WELCOME',
        64_900n,
        NOW,
        buyer,
      ),
    ).toBeNull();
  });
});
