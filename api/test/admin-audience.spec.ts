import { type ObjectLiteral, type Repository } from 'typeorm';
import { AdminAudienceService } from '../src/admin/admin-audience.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { ProfileEntity } from '../src/profile/entities/profile.entity';
import { HealthProfileEntity } from '../src/profile/entities/health-profile.entity';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { FoodLogEntity } from '../src/logs/entities/food-log.entity';

/// docs/09 §9 and docs/13 §5. Finding people, and the one rule about messaging them: a health
/// condition may target a CLINICAL message and nothing else.

const NOW = new Date('2026-09-18T10:00:00Z');

type Row = Record<string, unknown>;

function serviceWith({
  profiles = [
    { userId: 1, name: 'Asha K', goal: 'fat_loss' },
    { userId: 2, name: 'Bhavna R', goal: 'muscle_gain' },
    { userId: 3, name: 'Chetan S', goal: 'fat_loss' },
  ],
  health = [
    { userId: 1, version: 2, conditions: ['type2_diabetes'] },
    { userId: 1, version: 1, conditions: [] },
    { userId: 2, version: 1, conditions: ['pcos'] },
  ],
  subscriptions = [{ userId: 2, tier: 'PRO' }],
  users = [
    { id: 1, phone: '+919000000001' },
    { id: 2, phone: '+919000000002' },
    { id: 3, phone: null },
  ],
  logs = [{ userId: 1, diaryDate: '2026-09-17' }],
}: {
  profiles?: Row[];
  health?: Row[];
  subscriptions?: Row[];
  users?: Row[];
  logs?: Row[];
} = {}) {
  const sent: { userId: number; contentClass: string; dedupeKey?: string }[] =
    [];

  const matches = (row: Row, where: Record<string, unknown> | undefined) =>
    Object.entries(where ?? {}).every(([key, want]) => {
      const have = row[key];
      if (want && typeof want === 'object') {
        const operator = want as {
          type?: string;
          value?: unknown;
          _value?: unknown;
        };
        const value = operator.value ?? operator._value;
        if (Array.isArray(value)) return value.includes(have);
        if (typeof value === 'string') {
          // ILike('%text%')
          const needle = value.replaceAll('%', '').toLowerCase();
          return String(have ?? '')
            .toLowerCase()
            .includes(needle);
        }
        return false;
      }
      return have === want;
    });

  const repo = <T extends ObjectLiteral>(rows: Row[]) =>
    ({
      find: ({
        where,
        order,
      }: {
        where?: Record<string, unknown>;
        order?: Record<string, string>;
      } = {}) => {
        let out = rows.filter((r) => matches(r, where));
        const [field, direction] = Object.entries(order ?? {})[0] ?? [];
        if (field) {
          out = [...out].sort((a, b) =>
            direction === 'DESC'
              ? String(b[field]).localeCompare(String(a[field]))
              : String(a[field]).localeCompare(String(b[field])),
          );
        }
        return Promise.resolve(out);
      },
      findOne: ({
        where,
        order,
      }: {
        where?: Record<string, unknown>;
        order?: Record<string, string>;
      } = {}) => {
        let out = rows.filter((r) => matches(r, where));
        const [field, direction] = Object.entries(order ?? {})[0] ?? [];
        if (field) {
          out = [...out].sort((a, b) =>
            direction === 'DESC'
              ? String(b[field]).localeCompare(String(a[field]))
              : String(a[field]).localeCompare(String(b[field])),
          );
        }
        return Promise.resolve(out[0] ?? null);
      },
    }) as unknown as Repository<T>;

  const notifications = {
    notify: (input: {
      userId: number;
      contentClass: string;
      dedupeKey?: string;
    }) => {
      sent.push(input);
      return Promise.resolve({ id: `n${sent.length}` });
    },
  } as unknown as NotificationsService;

  return {
    service: new AdminAudienceService(
      repo<ProfileEntity>(profiles),
      repo<HealthProfileEntity>(health),
      repo<SubscriptionEntity>(subscriptions),
      repo<UserEntity>(users),
      repo<FoodLogEntity>(logs),
      notifications,
    ),
    sent,
  };
}

async function refusedCode(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (
      e as { getResponse(): { error: { code: string } } }
    ).getResponse();
    return body.error.code;
  }
  throw new Error('expected the call to be refused');
}

describe('finding somebody (docs/09 §9)', () => {
  it('should match a name, however it was typed', async () => {
    const { service } = serviceWith();

    const rows = await service.search('asha', undefined, NOW);

    expect(rows.map((r) => r.user_id)).toEqual([1]);
    expect(rows[0].name).toBe('Asha K');
  });

  it('should match a number without ever printing it in full (docs/13 §4)', async () => {
    const { service } = serviceWith();

    const rows = await service.search('9000000002', undefined, NOW);

    expect(rows.map((r) => r.user_id)).toEqual([2]);
    expect(rows[0].phone_masked).not.toContain('9000000002');
    expect(rows[0].phone_masked).toContain('…');
  });

  it('should narrow by goal and by tier together', async () => {
    const { service } = serviceWith();

    expect(
      (await service.search(undefined, { goal: 'fat_loss' }, NOW)).map(
        (r) => r.user_id,
      ),
    ).toEqual([1, 3]);
    expect(
      (
        await service.search(undefined, { goal: 'fat_loss', tier: 'PRO' }, NOW)
      ).map((r) => r.user_id),
    ).toEqual([]);
  });

  /// Conditions are versioned: an old answer is not what this person declares today.
  it('should read the latest health profile when filtering by condition', async () => {
    const { service } = serviceWith();

    const rows = await service.search(
      undefined,
      { conditions: ['type2_diabetes'] },
      NOW,
    );

    expect(rows.map((r) => r.user_id)).toEqual([1]);
  });

  it('should know when a search is a health read, and when it is not', () => {
    expect(AdminAudienceService.readsHealth({ conditions: ['pcos'] })).toBe(
      true,
    );
    expect(AdminAudienceService.readsHealth({ goal: 'fat_loss' })).toBe(false);
    expect(AdminAudienceService.readsHealth(undefined)).toBe(false);
  });

  it('should find who has gone quiet', async () => {
    const { service } = serviceWith();

    const rows = await service.search(undefined, { inactive_days: 3 }, NOW);

    expect(rows.map((r) => r.user_id)).toEqual([2, 3]);
  });
});

describe('sending to a segment (docs/13 §5)', () => {
  const message = {
    title: 'A new plan is ready',
    body: 'Open the app to see it.',
  };

  it('should refuse a commercial message aimed at a health condition', async () => {
    const { service, sent } = serviceWith();

    expect(
      await refusedCode(
        service.broadcast(
          {
            ...message,
            contentClass: 'commercial',
            segment: { conditions: ['type2_diabetes'] },
          },
          NOW,
        ),
      ),
    ).toBe('CONDITION_TARGETING_FORBIDDEN');
    expect(sent).toEqual([]);
  });

  it('should refuse a service message aimed at a health condition too', async () => {
    const { service } = serviceWith();

    expect(
      await refusedCode(
        service.broadcast(
          {
            ...message,
            contentClass: 'service',
            segment: { conditions: ['pcos'] },
          },
          NOW,
        ),
      ),
    ).toBe('CONDITION_TARGETING_FORBIDDEN');
  });

  it('should allow it for a clinical message, which is the one exception', async () => {
    const { service, sent } = serviceWith();

    const result = await service.broadcast(
      {
        title: 'About your medication and this plan',
        body: 'Please read this before your next week.',
        contentClass: 'clinical',
        segment: { conditions: ['type2_diabetes'] },
      },
      NOW,
    );

    expect(result).toMatchObject({ sent: 1, content_class: 'clinical' });
    expect(sent.map((s) => s.userId)).toEqual([1]);
  });

  it('should send to everybody when the segment says nothing', async () => {
    const { service, sent } = serviceWith();

    const result = await service.broadcast(
      { ...message, contentClass: 'service' },
      NOW,
    );

    expect(result.sent).toBe(3);
    expect(sent.every((s) => s.contentClass === 'service')).toBe(true);
  });

  it('should send to named people when they are named', async () => {
    const { service, sent } = serviceWith();

    await service.broadcast(
      { ...message, contentClass: 'service', segment: { user_ids: [2, 3] } },
      NOW,
    );

    expect(sent.map((s) => s.userId)).toEqual([2, 3]);
  });

  /// One key per send, so a retried request does not arrive twice.
  it('should key every message of one send the same way', async () => {
    const { service, sent } = serviceWith();

    await service.broadcast({ ...message, contentClass: 'service' }, NOW);

    expect(new Set(sent.map((s) => s.dedupeKey)).size).toBe(1);
  });
});
