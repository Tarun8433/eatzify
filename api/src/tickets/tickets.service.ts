import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import {
  MAX_OPEN_PER_USER,
  REOPEN_DAYS,
  TicketEntity,
  type TicketStatus,
} from './entities/ticket.entity';
import { TicketMessageEntity } from './entities/ticket-message.entity';
import { NotificationsService } from '../notifications/notifications.service';

export type TicketRow = {
  id: string;
  user_id: number;
  subject: string;
  status: TicketStatus;
  request_id: string | null;
  last_message_at: string;
  created_at: string;
};

export type TicketMessageView = {
  id: string;
  body: string;
  from_support: boolean;
  created_at: string;
};

export type TicketThread = TicketRow & { messages: TicketMessageView[] };

/// Who is still owed an answer. The support queue is exactly this set.
const AWAITING_SUPPORT: TicketStatus[] = ['new', 'open'];

/// What counts against [MAX_OPEN_PER_USER] — a conversation nobody has finished.
const UNFINISHED: TicketStatus[] = ['new', 'open', 'waiting_user'];

/// The longest a message may be. Long enough to describe a problem, short enough that the column is
/// not a place to paste a file.
const MAX_BODY = 4000;
const MAX_SUBJECT = 140;

/**
 * docs/09 §9 and docs/03 §5. Support conversations: the user's side and the admin's are the same
 * rows, read from two directions.
 *
 * `isSupport` is passed in by the controller that already checked the role, rather than read from a
 * token here — the service has one rule about it and the guard has the other, and putting both in
 * one place is how a service ends up trusting a caller's word for who it is.
 */
@Injectable()
export class TicketsService {
  constructor(
    @InjectRepository(TicketEntity)
    private readonly tickets: Repository<TicketEntity>,
    @InjectRepository(TicketMessageEntity)
    private readonly messages: Repository<TicketMessageEntity>,
    private readonly notifications: NotificationsService,
  ) {}

  async open(
    userId: number,
    input: { subject: string; body: string; requestId?: string | null },
    now = new Date(),
  ): Promise<TicketRow> {
    const subject = this.text(input.subject, MAX_SUBJECT, 'a subject');
    const body = this.text(input.body, MAX_BODY, 'a message');

    const unfinished = await this.tickets.count({
      where: { userId, status: In(UNFINISHED) },
    });
    if (unfinished >= MAX_OPEN_PER_USER) {
      throw new ConflictException({
        error: {
          code: 'TOO_MANY_TICKETS',
          user_message:
            'You already have several conversations open with us. Please reply on one of those instead.',
        },
      });
    }

    const ticket = await this.tickets.save(
      this.tickets.create({
        userId,
        subject,
        status: 'new',
        requestId: input.requestId ?? null,
        lastMessageAt: now,
      }),
    );

    await this.messages.save(
      this.messages.create({
        ticketId: ticket.id,
        senderUserId: userId,
        fromSupport: false,
        body,
        createdAt: now,
      }),
    );

    return this.toRow(ticket);
  }

  /// The reader's own conversations, the one they touched last at the top.
  async mine(userId: number): Promise<TicketRow[]> {
    const rows = await this.tickets.find({ where: { userId } });
    return [...rows]
      .sort((a, b) => this.at(b.lastMessageAt) - this.at(a.lastMessageAt))
      .map((row) => this.toRow(row));
  }

  async thread(
    id: string,
    viewer: { userId: number; isSupport: boolean },
  ): Promise<TicketThread> {
    const ticket = await this.readable(id, viewer);
    const messages = await this.messages.find({ where: { ticketId: id } });

    return {
      ...this.toRow(ticket),
      messages: [...messages]
        .sort((a, b) => this.at(a.createdAt) - this.at(b.createdAt))
        .map((row) => ({
          id: row.id,
          body: row.body,
          from_support: row.fromSupport,
          created_at: this.iso(row.createdAt),
        })),
    };
  }

  /**
   * One more message on an existing conversation.
   *
   * A resolved conversation reopens if the person comes back inside docs/03 §5's seven days; after
   * that the message is refused rather than swallowed, so somebody replying to a two-month-old
   * thread is told to start a new one instead of writing into a queue nobody reads.
   */
  async reply(
    id: string,
    sender: { userId: number; isSupport: boolean },
    rawBody: string,
    now = new Date(),
  ): Promise<TicketRow> {
    const body = this.text(rawBody, MAX_BODY, 'a message');
    const ticket = await this.readable(id, sender);

    if (ticket.status === 'closed' || !this.canWrite(ticket, now)) {
      throw new BadRequestException({
        error: {
          code: 'TICKET_CLOSED',
          user_message:
            'This conversation is closed. Please start a new one and we will pick it up.',
        },
      });
    }

    await this.messages.save(
      this.messages.create({
        ticketId: ticket.id,
        senderUserId: sender.userId,
        fromSupport: sender.isSupport,
        body,
        createdAt: now,
      }),
    );

    ticket.status = sender.isSupport ? 'waiting_user' : 'open';
    ticket.lastMessageAt = now;
    ticket.closedAt = null;
    const saved = await this.tickets.save(ticket);

    if (sender.isSupport) {
      await this.notifications.notify({
        userId: ticket.userId,
        kind: 'ticket_reply',
        contentClass: 'service',
        title: 'Support replied',
        body: ticket.subject,
        data: { ticket_id: ticket.id },
      });
    }

    return this.toRow(saved);
  }

  /// Support says it is done. Reopenable for [REOPEN_DAYS] from this moment.
  async resolve(id: string, now = new Date()): Promise<TicketRow> {
    const ticket = await this.byId(id);
    ticket.status = 'resolved';
    ticket.closedAt = now;
    const saved = await this.tickets.save(ticket);

    await this.notifications.notify({
      userId: ticket.userId,
      kind: 'ticket_resolved',
      contentClass: 'service',
      title: 'Your support request is resolved',
      body: ticket.subject,
      data: { ticket_id: ticket.id },
    });

    return this.toRow(saved);
  }

  /// Final. docs/13 §6's two-year retention runs from here.
  async close(id: string, now = new Date()): Promise<TicketRow> {
    const ticket = await this.byId(id);
    ticket.status = 'closed';
    ticket.closedAt = ticket.closedAt ?? now;
    return this.toRow(await this.tickets.save(ticket));
  }

  /**
   * The support queue. With no status it is the work: everything still waiting on us, oldest first,
   * because a queue sorted newest-first is a queue with a bottom nobody reaches.
   */
  async queue(status?: TicketStatus, limit = 100): Promise<TicketRow[]> {
    const rows = await this.tickets.find({
      where: status ? { status } : { status: In(AWAITING_SUPPORT) },
    });

    return [...rows]
      .sort((a, b) => this.at(a.lastMessageAt) - this.at(b.lastMessageAt))
      .slice(0, limit)
      .map((row) => this.toRow(row));
  }

  private canWrite(ticket: TicketEntity, now: Date): boolean {
    if (ticket.status !== 'resolved') return true;
    if (!ticket.closedAt) return true;

    const days = (this.at(now) - this.at(ticket.closedAt)) / 86_400_000;
    return days <= REOPEN_DAYS;
  }

  private async byId(id: string): Promise<TicketEntity> {
    const ticket = await this.tickets.findOne({ where: { id } });
    if (!ticket) {
      throw new NotFoundException({
        error: {
          code: 'TICKET_NOT_FOUND',
          user_message: 'We could not find that conversation.',
        },
      });
    }
    return ticket;
  }

  /// Somebody else's conversation is not "forbidden", it is not there: a 403 would confirm that a
  /// ticket with that id exists.
  private async readable(
    id: string,
    viewer: { userId: number; isSupport: boolean },
  ): Promise<TicketEntity> {
    const ticket = await this.byId(id);
    if (!viewer.isSupport && ticket.userId !== viewer.userId) {
      throw new NotFoundException({
        error: {
          code: 'TICKET_NOT_FOUND',
          user_message: 'We could not find that conversation.',
        },
      });
    }
    return ticket;
  }

  private text(value: string, max: number, what: string): string {
    const trimmed = (value ?? '').trim();
    if (!trimmed || trimmed.length > max) {
      throw new BadRequestException({
        error: {
          code: 'TICKET_INVALID',
          user_message: `Please write ${what} of up to ${max} characters.`,
        },
      });
    }
    return trimmed;
  }

  private at(value: Date | string): number {
    return value instanceof Date ? value.getTime() : new Date(value).getTime();
  }

  private iso(value: Date | string): string {
    return value instanceof Date ? value.toISOString() : value;
  }

  private toRow(row: TicketEntity): TicketRow {
    return {
      id: row.id,
      user_id: row.userId,
      subject: row.subject,
      status: row.status,
      request_id: row.requestId,
      last_message_at: this.iso(row.lastMessageAt),
      created_at: this.iso(row.createdAt ?? row.lastMessageAt),
    };
  }
}
