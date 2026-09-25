import {
  ForbiddenException,
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, LessThan, Not, Repository } from 'typeorm';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { MessageEntity } from './entities/message.entity';
import { CoachGrantEntity } from './entities/coach-grant.entity';
import { CoachGrantService } from './coach-grant.service';
import { NotificationsService } from '../notifications/notifications.service';

export type MessageView = {
  id: string;
  /// Whether the CALLER wrote it. Which side of the bubble it goes on, decided by the server so
  /// two clients never disagree about it.
  mine: boolean;
  sender_user_id: number;
  body: string;
  read_at: string | null;
  created_at: string;
};

export type ThreadView = {
  /// The person on the other end, from the caller's point of view.
  other_user_id: number;
  name: string;
  /// Whether the caller is the coach in this thread.
  i_am_coach: boolean;
  last_message: string | null;
  last_at: string | null;
  unread: number;
};

/// docs/09 §6 pages backwards through a thread; a screenful at a time.
export const MESSAGE_PAGE = 50;
export const MAX_MESSAGE_LENGTH = 2000;

/**
 * In-app chat between a coach and their client (docs/02 FR-5.5).
 *
 * **Every call re-checks the grant.** docs/10 §3 makes `chat` a scope the client gives and can take
 * back, and a thread is not a place that stays open because it was open yesterday: a revoked grant
 * closes it for both sides, in the middle of a conversation if that is when it happens.
 */
@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(MessageEntity)
    private readonly messages: Repository<MessageEntity>,
    @InjectRepository(CoachGrantEntity)
    private readonly grants: Repository<CoachGrantEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    private readonly grantService: CoachGrantService,
    private readonly notifications: NotificationsService,
  ) {}

  /// Who the caller can talk to right now, newest conversation first.
  async threads(userId: number, now: Date): Promise<ThreadView[]> {
    const rows = await this.grants.find({
      where: [
        { coachUserId: userId, status: 'active' },
        { clientUserId: userId, status: 'active' },
      ],
    });

    const threads: ThreadView[] = [];
    for (const grant of rows) {
      if (grant.expiresAt <= now) continue;
      const scopes = await this.grantService.scopesFor(
        grant.coachUserId,
        grant.clientUserId,
        now,
      );
      if (!scopes.includes('chat')) continue;

      const iAmCoach = grant.coachUserId === userId;
      const otherId = iAmCoach ? grant.clientUserId : grant.coachUserId;

      const [last, unread] = await Promise.all([
        this.messages.findOne({
          where: {
            coachUserId: grant.coachUserId,
            clientUserId: grant.clientUserId,
          },
          order: { createdAt: 'DESC' },
        }),
        this.messages.count({
          where: {
            coachUserId: grant.coachUserId,
            clientUserId: grant.clientUserId,
            senderUserId: Not(userId),
            readAt: IsNull(),
          },
        }),
      ]);

      threads.push({
        other_user_id: otherId,
        name: await this.nameOf(otherId),
        i_am_coach: iAmCoach,
        last_message: last?.body ?? null,
        last_at: last?.createdAt?.toISOString() ?? null,
        unread,
      });
    }

    return threads.sort((a, b) =>
      (b.last_at ?? '').localeCompare(a.last_at ?? ''),
    );
  }

  /// One thread, newest first. [before] pages backwards from a message's `created_at`.
  async history(
    userId: number,
    otherUserId: number,
    now: Date,
    options: { before?: string; limit?: number } = {},
  ): Promise<MessageView[]> {
    const pair = await this.pairFor(userId, otherUserId, now);
    const before = options.before ? new Date(options.before) : null;

    const rows = await this.messages.find({
      where: {
        coachUserId: pair.coachUserId,
        clientUserId: pair.clientUserId,
        ...(before && !Number.isNaN(before.getTime())
          ? { createdAt: LessThan(before) }
          : {}),
      },
      order: { createdAt: 'DESC' },
      take: Math.min(options.limit ?? MESSAGE_PAGE, MESSAGE_PAGE),
    });

    return rows.map((row) => this.toView(row, userId));
  }

  /// docs/09 §6: `POST /coach/messages`.
  async send(
    userId: number,
    otherUserId: number,
    body: string,
    now: Date,
  ): Promise<MessageView> {
    const pair = await this.pairFor(userId, otherUserId, now);
    const text = body.trim();

    if (text.length === 0 || text.length > MAX_MESSAGE_LENGTH) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'MESSAGE_LENGTH',
          user_message: 'Please write a message before sending it.',
        },
      });
    }

    const saved = await this.messages.save(
      this.messages.create({
        coachUserId: pair.coachUserId,
        clientUserId: pair.clientUserId,
        senderUserId: userId,
        body: text,
      }),
    );

    // The other side may not have the app open. The message itself is not repeated in the notice —
    // a lock screen is not the place for somebody's diet conversation (docs/13 §5).
    await this.notifications.notify({
      userId: otherUserId,
      kind: 'message_received',
      contentClass: 'service',
      title: 'New message',
      body: `${await this.nameOf(userId)} sent you a message.`,
      data: { other_user_id: userId },
      dedupeKey: `message:${saved.id}`,
    });

    return this.toView(saved, userId);
  }

  /// Everything the other side wrote in this thread is now read.
  async markRead(
    userId: number,
    otherUserId: number,
    now: Date,
  ): Promise<void> {
    const pair = await this.pairFor(userId, otherUserId, now);

    await this.messages.update(
      {
        coachUserId: pair.coachUserId,
        clientUserId: pair.clientUserId,
        senderUserId: Not(userId),
        readAt: IsNull(),
      },
      { readAt: now },
    );
  }

  /// How many unread messages the caller has, across every thread — the badge on the tab.
  async unreadCount(userId: number, now: Date): Promise<number> {
    const threads = await this.threads(userId, now);
    return threads.reduce((sum, thread) => sum + thread.unread, 0);
  }

  /**
   * Which of the two is the coach, and whether they may talk at all.
   *
   * Throws 403 rather than 404: the two of them know each other — a client whose coach revoked the
   * chat scope is owed an explanation, not a pretence that the conversation never existed.
   */
  async pairFor(
    userId: number,
    otherUserId: number,
    now: Date,
  ): Promise<{ coachUserId: number; clientUserId: number; iAmCoach: boolean }> {
    const grant = await this.grants.findOne({
      where: [
        { coachUserId: userId, clientUserId: otherUserId },
        { coachUserId: otherUserId, clientUserId: userId },
      ],
    });

    const scopes = grant
      ? await this.grantService.scopesFor(
          grant.coachUserId,
          grant.clientUserId,
          now,
        )
      : [];

    if (!grant || !scopes.includes('chat')) {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: {
          code: 'CHAT_NOT_ALLOWED',
          user_message: 'This conversation is not open any more.',
        },
      });
    }

    return {
      coachUserId: grant.coachUserId,
      clientUserId: grant.clientUserId,
      iAmCoach: grant.coachUserId === userId,
    };
  }

  /// A phone-OTP signup never fills `user.firstName` — the name is asked for at onboarding and
  /// lands on the profile, which is why the roster reads both (the same lesson, in one place less).
  private async nameOf(userId: number): Promise<string> {
    const [user, profile] = await Promise.all([
      this.users.findOne({ where: { id: userId } }),
      this.profiles.findOne({ where: { userId } }),
    ]);

    const onUser = `${user?.firstName ?? ''} ${user?.lastName ?? ''}`.trim();
    return onUser.length > 0 ? onUser : (profile?.name?.trim() ?? '');
  }

  private toView(row: MessageEntity, readerId: number): MessageView {
    return {
      id: row.id,
      mine: row.senderUserId === readerId,
      sender_user_id: row.senderUserId,
      body: row.body,
      read_at: row.readAt?.toISOString() ?? null,
      created_at: row.createdAt.toISOString(),
    };
  }
}

/// Exported for the gateway, which needs the same "may these two talk" answer before it lets a
/// socket into a room.
export type ThreadPair = Awaited<ReturnType<MessagesService['pairFor']>>;
