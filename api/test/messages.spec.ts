import { type Repository } from 'typeorm';
import { MessageEntity } from '../src/coach/entities/message.entity';
import { CoachGrantEntity } from '../src/coach/entities/coach-grant.entity';
import { CoachGrantService } from '../src/coach/coach-grant.service';
import {
  MAX_MESSAGE_LENGTH,
  MessagesService,
} from '../src/coach/messages.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { ProfileEntity } from '../src/profile/entities/profile.entity';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import type { GrantScope } from '../src/coach/entities/coach-grant.entity';

/// docs/02 FR-5.5 and docs/10 §3. A coach and a client can talk for exactly as long as the client
/// allows it — the `chat` scope is checked on every call, not once when the screen opened.

const NOW = new Date('2026-09-18T10:00:00Z');
const COACH = 1;
const CLIENT = 7;

type Msg = Partial<MessageEntity>;

function serviceWith({
  rows = [],
  scopes = ['basic', 'chat'],
  grant = {
    coachUserId: COACH,
    clientUserId: CLIENT,
    status: 'active',
    expiresAt: new Date('2027-01-01T00:00:00Z'),
  },
}: {
  rows?: Msg[];
  scopes?: GrantScope[];
  grant?: Partial<CoachGrantEntity> | null;
} = {}) {
  const sent: { userId: number; kind: string; body: string }[] = [];
  const updates: {
    where: Record<string, unknown>;
    set: Record<string, unknown>;
  }[] = [];

  const messages = {
    rows,
    create: (row: Msg) => row,
    save: (row: Msg) => {
      const saved = {
        id: `m${rows.length + 1}`,
        createdAt: NOW,
        readAt: null,
        ...row,
      };
      rows.push(saved);
      return Promise.resolve(saved);
    },
    find: ({ take }: { take?: number }) =>
      Promise.resolve([...rows].reverse().slice(0, take ?? rows.length)),
    findOne: () => Promise.resolve(rows[rows.length - 1] ?? null),
    count: () =>
      Promise.resolve(
        rows.filter((r) => r.senderUserId !== COACH && !r.readAt).length,
      ),
    update: (where: Record<string, unknown>, set: Record<string, unknown>) => {
      updates.push({ where, set });
      return Promise.resolve({ affected: 1 });
    },
  } as unknown as Repository<MessageEntity>;

  const grants = {
    find: () => Promise.resolve(grant ? [grant] : []),
    findOne: () => Promise.resolve(grant),
  } as unknown as Repository<CoachGrantEntity>;

  const users = {
    findOne: ({ where }: { where: { id: number } }) =>
      Promise.resolve({
        id: where.id,
        firstName: where.id === COACH ? 'A' : 'B',
        lastName: 'N',
      }),
  } as unknown as Repository<UserEntity>;

  const profiles = {
    findOne: () => Promise.resolve(null),
  } as unknown as Repository<ProfileEntity>;

  const grantService = {
    scopesFor: () => Promise.resolve(scopes),
  } as unknown as CoachGrantService;

  const notifications = {
    notify: (input: { userId: number; kind: string; body: string }) => {
      sent.push(input);
      return Promise.resolve({ id: 'n1' });
    },
  } as unknown as NotificationsService;

  return {
    service: new MessagesService(
      messages,
      grants,
      users,
      profiles,
      grantService,
      notifications,
    ),
    rows,
    sent,
    updates,
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

describe('sending a message (docs/09 §6)', () => {
  it('should store it against the pair, with who wrote it', async () => {
    const { service, rows } = serviceWith();

    const view = await service.send(
      COACH,
      CLIENT,
      '  How was the week?  ',
      NOW,
    );

    expect(rows[0]).toMatchObject({
      coachUserId: COACH,
      clientUserId: CLIENT,
      senderUserId: COACH,
      body: 'How was the week?',
    });
    expect(view.mine).toBe(true);
  });

  it('should work the same way when the client writes back', async () => {
    const { service, rows } = serviceWith();

    const view = await service.send(CLIENT, COACH, 'Good, sleep was poor', NOW);

    expect(rows[0]).toMatchObject({
      coachUserId: COACH,
      clientUserId: CLIENT,
      senderUserId: CLIENT,
    });
    expect(view.mine).toBe(true);
  });

  /// docs/13 §5: a lock screen is not the place for somebody's diet conversation.
  it('should tell the other side without repeating what was said', async () => {
    const { service, sent } = serviceWith();

    await service.send(COACH, CLIENT, 'Your protein is low this week', NOW);

    expect(sent[0]).toMatchObject({ userId: CLIENT, kind: 'message_received' });
    expect(sent[0].body).not.toContain('protein');
  });

  it('should refuse an empty message and one nobody would read', async () => {
    const { service } = serviceWith();

    expect(await refusedCode(service.send(COACH, CLIENT, '   ', NOW))).toBe(
      'MESSAGE_LENGTH',
    );
    expect(
      await refusedCode(
        service.send(COACH, CLIENT, 'x'.repeat(MAX_MESSAGE_LENGTH + 1), NOW),
      ),
    ).toBe('MESSAGE_LENGTH');
  });
});

describe('who may talk (docs/10 §3)', () => {
  it('should refuse when the client never granted chat', async () => {
    const { service } = serviceWith({ scopes: ['basic', 'progress'] });

    expect(await refusedCode(service.send(COACH, CLIENT, 'Hello', NOW))).toBe(
      'CHAT_NOT_ALLOWED',
    );
    expect(await refusedCode(service.history(COACH, CLIENT, NOW))).toBe(
      'CHAT_NOT_ALLOWED',
    );
  });

  it('should refuse two people with no grant between them at all', async () => {
    const { service } = serviceWith({ grant: null });

    expect(await refusedCode(service.send(COACH, 99, 'Hello', NOW))).toBe(
      'CHAT_NOT_ALLOWED',
    );
  });

  /// A revoked grant closes the thread for both sides, mid-conversation if that is when it happens.
  it('should close a thread the moment the scope goes away', async () => {
    const open = serviceWith();
    await open.service.send(COACH, CLIENT, 'Hello', NOW);

    const revoked = serviceWith({ rows: open.rows, scopes: ['basic'] });
    expect(await refusedCode(revoked.service.history(CLIENT, COACH, NOW))).toBe(
      'CHAT_NOT_ALLOWED',
    );
  });
});

describe('reading a thread', () => {
  it('should say which messages are the reader’s own', async () => {
    const { service, rows } = serviceWith();
    await service.send(COACH, CLIENT, 'How was the week?', NOW);
    await service.send(CLIENT, COACH, 'Good', NOW);

    const asClient = await service.history(CLIENT, COACH, NOW);

    expect(rows).toHaveLength(2);
    expect(asClient.map((m) => m.mine)).toEqual([true, false]);
  });

  it('should mark only what the other side wrote as read', async () => {
    const { service, updates } = serviceWith();

    await service.markRead(CLIENT, COACH, NOW);

    expect(updates[0].where).toMatchObject({
      coachUserId: COACH,
      clientUserId: CLIENT,
    });
    expect(updates[0].set.readAt).toBe(NOW);
  });

  it('should list the threads the caller may still use', async () => {
    const { service } = serviceWith();
    await service.send(COACH, CLIENT, 'Anything I can help with?', NOW);

    const threads = await service.threads(CLIENT, NOW);

    expect(threads).toHaveLength(1);
    expect(threads[0]).toMatchObject({
      other_user_id: COACH,
      i_am_coach: false,
      last_message: 'Anything I can help with?',
    });
  });

  it('should leave out a thread whose chat scope has gone', async () => {
    const { service } = serviceWith({ scopes: ['progress'] });

    expect(await service.threads(CLIENT, NOW)).toEqual([]);
  });

  it('should leave out an expired grant', async () => {
    const { service } = serviceWith({
      grant: {
        coachUserId: COACH,
        clientUserId: CLIENT,
        status: 'active',
        expiresAt: new Date('2026-01-01T00:00:00Z'),
      },
    });

    expect(await service.threads(CLIENT, NOW)).toEqual([]);
  });
});
