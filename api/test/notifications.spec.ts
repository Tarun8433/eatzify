import { QueryFailedError, type Repository } from 'typeorm';
import { NotificationEntity } from '../src/notifications/entities/notification.entity';
import {
  MAX_NOTIFICATIONS,
  NotificationsService,
} from '../src/notifications/notifications.service';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { MailService } from '../src/mail/mail.service';

/// docs/13 §5 and docs/14 §6. Messages the app can list, and the "send this once" rule the renewal
/// sweep in docs/11 §8 depends on.

type Row = Partial<NotificationEntity>;

function fakeRepo(rows: Row[] = []) {
  const repo = {
    rows,
    /// Set to make the next save collide on the dedupe index.
    duplicate: false,
    updates: [] as {
      where: Record<string, unknown>;
      set: Record<string, unknown>;
    }[],
    create: (row: Row) => row,
    save: (row: Row) => {
      if (repo.duplicate) {
        repo.duplicate = false;
        throw new QueryFailedError('INSERT', [], {
          code: '23505',
        } as unknown as Error);
      }
      const saved = {
        id: `n${rows.length + 1}`,
        createdAt: new Date(),
        ...row,
      };
      rows.push(saved);
      return Promise.resolve(saved);
    },
    find: ({ take }: { take?: number }) =>
      Promise.resolve(rows.slice(0, take ?? rows.length)),
    count: () => Promise.resolve(rows.filter((r) => !r.readAt).length),
    update: (where: Record<string, unknown>, set: Record<string, unknown>) => {
      repo.updates.push({ where, set });
      return Promise.resolve({ affected: 1 });
    },
  };
  return repo;
}

function serviceWith(
  repo: ReturnType<typeof fakeRepo>,
  user: Partial<UserEntity> | null = { id: 1, email: 'someone@example.test' },
  sent: { to: string; title: string }[] = [],
) {
  const users = {
    findOne: () => Promise.resolve(user),
  } as unknown as Repository<UserEntity>;
  const mail = {
    notification: ({ to, data }: { to: string; data: { title: string } }) => {
      sent.push({ to, title: data.title });
      return Promise.resolve();
    },
  } as unknown as MailService;

  return new NotificationsService(
    repo as unknown as Repository<NotificationEntity>,
    users,
    mail,
  );
}

const notice = {
  userId: 1,
  kind: 'renewal_t7',
  contentClass: 'service' as const,
  title: 'Your plan renews on 24 September',
  body: '₹999 will be charged on 24 September.',
};

describe('sending a notification', () => {
  it('should keep what the app needs to show it', async () => {
    const repo = fakeRepo();
    const saved = await serviceWith(repo).notify({
      ...notice,
      data: { tier: 'PRO' },
    });

    expect(saved).toMatchObject({
      userId: 1,
      kind: 'renewal_t7',
      contentClass: 'service',
      data: { tier: 'PRO' },
      dedupeKey: null,
    });
  });

  /// docs/13 §5: the class decides who may be targeted, so an unknown one is a programming error,
  /// not a row.
  it('should refuse a content class nobody can check the targeting rules against', async () => {
    const repo = fakeRepo();
    await expect(
      serviceWith(repo).notify({
        ...notice,
        contentClass: 'marketing' as never,
      }),
    ).rejects.toThrow('Unknown content class');
    expect(repo.rows).toHaveLength(0);
  });

  /// The sweep runs daily and must be safe to run twice.
  it('should send a keyed notice once, however often it is asked for', async () => {
    const repo = fakeRepo();
    const service = serviceWith(repo);

    const first = await service.notify({
      ...notice,
      dedupeKey: 'renewal_t7:sub-1',
    });
    repo.duplicate = true;
    const second = await service.notify({
      ...notice,
      dedupeKey: 'renewal_t7:sub-1',
    });

    expect(first).not.toBeNull();
    expect(second).toBeNull();
    expect(repo.rows).toHaveLength(1);
  });

  it('should not swallow a database error that is not the duplicate', async () => {
    const repo = fakeRepo();
    repo.save = () => {
      throw new QueryFailedError('INSERT', [], {
        code: '42P01',
      } as unknown as Error);
    };

    await expect(serviceWith(repo).notify(notice)).rejects.toThrow(
      QueryFailedError,
    );
  });
});

describe('the email copy of a notice', () => {
  it('should go out when the account has an address', async () => {
    const sent: { to: string; title: string }[] = [];
    await serviceWith(
      fakeRepo(),
      { id: 1, email: 'someone@example.test' },
      sent,
    ).notify({
      ...notice,
      alsoEmail: true,
    });

    expect(sent).toEqual([{ to: 'someone@example.test', title: notice.title }]);
  });

  it('should be skipped for a phone-only account, which is most of them', async () => {
    const sent: { to: string; title: string }[] = [];
    await serviceWith(fakeRepo(), { id: 1, email: null }, sent).notify({
      ...notice,
      alsoEmail: true,
    });

    expect(sent).toEqual([]);
  });

  it('should never cost the notice itself when the mail server is down', async () => {
    const repo = fakeRepo();
    const service = new NotificationsService(
      repo as unknown as Repository<NotificationEntity>,
      {
        findOne: () => Promise.resolve({ id: 1, email: 'x@example.test' }),
      } as never,
      { notification: () => Promise.reject(new Error('smtp down')) } as never,
    );

    await expect(
      service.notify({ ...notice, alsoEmail: true }),
    ).resolves.not.toBeNull();
    expect(repo.rows).toHaveLength(1);
  });
});

describe('the list', () => {
  it('should count what is unread and cap what it returns', async () => {
    const repo = fakeRepo([
      { id: 'n1', userId: 1, readAt: null, createdAt: new Date() },
      { id: 'n2', userId: 1, readAt: new Date(), createdAt: new Date() },
    ]);

    const view = await serviceWith(repo).list(1, { limit: 500 });

    expect(view.unread_count).toBe(1);
    expect(view.items.length).toBeLessThanOrEqual(MAX_NOTIFICATIONS);
  });

  it('should only ever mark the reader’s own notice as read', async () => {
    const repo = fakeRepo();
    await serviceWith(repo).markRead(7, 'n1');

    expect(repo.updates[0].where).toMatchObject({ id: 'n1', userId: 7 });
    expect(repo.updates[0].set.readAt).toBeInstanceOf(Date);
  });

  it('should mark every unread one at once', async () => {
    const repo = fakeRepo();
    await serviceWith(repo).markAllRead(7);

    expect(repo.updates[0].where).toMatchObject({ userId: 7 });
  });
});
