import { type Repository } from 'typeorm';
import { TicketsService } from '../src/tickets/tickets.service';
import {
  MAX_OPEN_PER_USER,
  TicketEntity,
  type TicketStatus,
} from '../src/tickets/entities/ticket.entity';
import { TicketMessageEntity } from '../src/tickets/entities/ticket-message.entity';
import { NotificationsService } from '../src/notifications/notifications.service';

/// docs/09 §9 (`GET /admin/tickets`, `POST /admin/tickets/{id}/reply`) and docs/03 §5's states:
/// `new → open → waiting_user → resolved → closed`, reopenable within 7 days.

const NOW = new Date('2026-09-18T10:00:00Z');
const USER = 7;
const OTHER_USER = 8;
const SUPPORT = 3;

const later = (days: number) =>
  new Date(NOW.getTime() + days * 24 * 60 * 60 * 1000);

type Ticket = Partial<TicketEntity>;
type Message = Partial<TicketMessageEntity>;

function serviceWith(seed: Ticket[] = [], seedMessages: Message[] = []) {
  const tickets = [...seed];
  const messages = [...seedMessages];
  const sent: { kind: string; userId: number }[] = [];

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

  const repo = <T extends { id?: string }>(rows: T[], prefix: string) =>
    ({
      create: (row: T) => row,
      save: (row: T) => {
        const at = rows.findIndex((r) => r.id && r.id === row.id);
        const saved = { id: row.id ?? `${prefix}${rows.length + 1}`, ...row };
        if (at >= 0) rows[at] = saved;
        else rows.push(saved);
        return Promise.resolve(saved);
      },
      find: ({ where }: { where?: Record<string, unknown> } = {}) =>
        Promise.resolve(rows.filter((r) => matches(r as never, where ?? {}))),
      findOne: ({ where }: { where: Record<string, unknown> }) =>
        Promise.resolve(rows.find((r) => matches(r as never, where)) ?? null),
      count: ({ where }: { where: Record<string, unknown> }) =>
        Promise.resolve(rows.filter((r) => matches(r as never, where)).length),
    }) as unknown as Repository<T>;

  const notifications = {
    notify: (input: { kind: string; userId: number }) => {
      sent.push({ kind: input.kind, userId: input.userId });
      return Promise.resolve(null);
    },
  } as unknown as NotificationsService;

  return {
    service: new TicketsService(
      repo(tickets as never[], 't') as Repository<TicketEntity>,
      repo(messages as never[], 'm') as Repository<TicketMessageEntity>,
      notifications,
    ),
    tickets,
    messages,
    sent,
  };
}

const ticket = (over: Ticket = {}): Ticket => ({
  id: 't1',
  userId: USER,
  subject: 'Payment did not go through',
  status: 'new',
  requestId: null,
  lastMessageAt: NOW,
  closedAt: null,
  createdAt: NOW,
  ...over,
});

async function refusedCode(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (
      e as { getResponse(): { error?: { code: string } } }
    ).getResponse();
    return body.error?.code ?? 'NO_CODE';
  }
  throw new Error('expected the call to be refused');
}

describe('opening a ticket (docs/09 §9)', () => {
  it('should keep the first message and the request id it complains about', async () => {
    const { service, tickets, messages } = serviceWith();

    const view = await service.open(
      USER,
      { subject: 'Payment failed', body: 'Paid twice.', requestId: 'req-42' },
      NOW,
    );

    expect(view).toMatchObject({ status: 'new', request_id: 'req-42' });
    expect(tickets).toHaveLength(1);
    expect(messages[0]).toMatchObject({
      ticketId: view.id,
      senderUserId: USER,
      fromSupport: false,
      body: 'Paid twice.',
    });
  });

  it('should refuse a sixth open conversation from the same person', async () => {
    const open: TicketStatus[] = ['new', 'open', 'waiting_user', 'open', 'new'];
    const { service, tickets } = serviceWith(
      open.map((status, i) => ticket({ id: `t${i}`, status })),
    );
    expect(tickets).toHaveLength(MAX_OPEN_PER_USER);

    expect(
      await refusedCode(
        service.open(USER, { subject: 'Another', body: 'And another' }, NOW),
      ),
    ).toBe('TOO_MANY_TICKETS');
  });

  /// A resolved conversation is not an open one — somebody who was helped five times may still ask.
  it('should not count resolved conversations against the cap', async () => {
    const { service } = serviceWith(
      Array.from({ length: MAX_OPEN_PER_USER }, (_, i) =>
        ticket({ id: `t${i}`, status: 'resolved', closedAt: NOW }),
      ),
    );

    await expect(
      service.open(USER, { subject: 'New one', body: 'Hello' }, NOW),
    ).resolves.toMatchObject({ status: 'new' });
  });
});

describe('the conversation (docs/03 §5)', () => {
  it('should move the ball to support when the user writes', async () => {
    const { service, tickets } = serviceWith([
      ticket({ status: 'waiting_user' }),
    ]);

    await service.reply(
      't1',
      { userId: USER, isSupport: false },
      'Still charged twice.',
      later(1),
    );

    expect(tickets[0]).toMatchObject({
      status: 'open',
      lastMessageAt: later(1),
    });
  });

  it('should move it back, and tell the person, when support writes', async () => {
    const { service, tickets, messages, sent } = serviceWith([
      ticket({ status: 'open' }),
    ]);

    await service.reply(
      't1',
      { userId: SUPPORT, isSupport: true },
      'Refund is on its way.',
      later(1),
    );

    expect(tickets[0]).toMatchObject({ status: 'waiting_user' });
    expect(messages[0]).toMatchObject({
      fromSupport: true,
      senderUserId: SUPPORT,
    });
    expect(sent).toEqual([{ kind: 'ticket_reply', userId: USER }]);
  });

  it('should not hand somebody else their conversation', async () => {
    const { service } = serviceWith([ticket()]);

    await expect(
      service.thread('t1', { userId: OTHER_USER, isSupport: false }),
    ).rejects.toMatchObject({ status: 404 });

    expect(
      await refusedCode(
        service.reply(
          't1',
          { userId: OTHER_USER, isSupport: false },
          'Hi',
          NOW,
        ),
      ),
    ).toBe('TICKET_NOT_FOUND');
  });

  it('should read a whole thread in order for the person it belongs to', async () => {
    const { service } = serviceWith(
      [ticket()],
      [
        {
          id: 'm2',
          ticketId: 't1',
          senderUserId: SUPPORT,
          fromSupport: true,
          body: 'Looking into it.',
          createdAt: later(1),
        },
        {
          id: 'm1',
          ticketId: 't1',
          senderUserId: USER,
          fromSupport: false,
          body: 'Paid twice.',
          createdAt: NOW,
        },
      ],
    );

    const view = await service.thread('t1', { userId: USER, isSupport: false });

    expect(view.messages.map((m) => m.body)).toEqual([
      'Paid twice.',
      'Looking into it.',
    ]);
  });
});

describe('resolving and reopening (docs/03 §5)', () => {
  it('should start the clock when support resolves it', async () => {
    const { service, tickets, sent } = serviceWith([
      ticket({ status: 'open' }),
    ]);

    await service.resolve('t1', later(2));

    expect(tickets[0]).toMatchObject({
      status: 'resolved',
      closedAt: later(2),
    });
    expect(sent).toEqual([{ kind: 'ticket_resolved', userId: USER }]);
  });

  it('should let the person reopen it within seven days', async () => {
    const { service, tickets } = serviceWith([
      ticket({ status: 'resolved', closedAt: NOW }),
    ]);

    await service.reply(
      't1',
      { userId: USER, isSupport: false },
      'It happened again.',
      later(6),
    );

    expect(tickets[0]).toMatchObject({ status: 'open', closedAt: null });
  });

  it('should ask for a new one after the window, rather than losing the message', async () => {
    const { service, messages } = serviceWith([
      ticket({ status: 'resolved', closedAt: NOW }),
    ]);

    expect(
      await refusedCode(
        service.reply(
          't1',
          { userId: USER, isSupport: false },
          'It happened again.',
          later(8),
        ),
      ),
    ).toBe('TICKET_CLOSED');
    expect(messages).toEqual([]);
  });

  it('should refuse a reply to a closed conversation from either side', async () => {
    const { service } = serviceWith([
      ticket({ status: 'closed', closedAt: NOW }),
    ]);

    expect(
      await refusedCode(
        service.reply(
          't1',
          { userId: SUPPORT, isSupport: true },
          'Hi',
          later(1),
        ),
      ),
    ).toBe('TICKET_CLOSED');
  });
});

describe('the support queue (docs/09 §9)', () => {
  it('should show the ones waiting on support first-written first', async () => {
    const { service } = serviceWith([
      ticket({ id: 't1', status: 'open', lastMessageAt: later(2) }),
      ticket({ id: 't2', status: 'new', lastMessageAt: NOW }),
      ticket({ id: 't3', status: 'waiting_user', lastMessageAt: later(1) }),
      ticket({ id: 't4', status: 'resolved', lastMessageAt: later(3) }),
    ]);

    const queue = await service.queue();

    expect(queue.map((t) => t.id)).toEqual(['t2', 't1']);
  });

  it('should show one named state when asked for it', async () => {
    const { service } = serviceWith([
      ticket({ id: 't1', status: 'open' }),
      ticket({ id: 't2', status: 'resolved', closedAt: NOW }),
    ]);

    expect((await service.queue('resolved')).map((t) => t.id)).toEqual(['t2']);
  });

  /// Rule 5: a queue row carries an id, never a name or a number.
  it('should carry no personal detail in a queue row', async () => {
    const { service } = serviceWith([ticket({ id: 't1', status: 'open' })]);

    const [row] = await service.queue();

    expect(Object.keys(row).sort()).toEqual(
      [
        'created_at',
        'id',
        'last_message_at',
        'request_id',
        'status',
        'subject',
        'user_id',
      ].sort(),
    );
  });
});
