import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, LessThan, QueryFailedError, Repository } from 'typeorm';
import {
  CONTENT_CLASSES,
  NotificationEntity,
  type ContentClass,
} from './entities/notification.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { MailService } from '../mail/mail.service';

export type NotificationView = {
  id: string;
  kind: string;
  content_class: ContentClass;
  title: string;
  body: string;
  data: Record<string, unknown> | null;
  read_at: string | null;
  created_at: string;
};

export type NotificationListView = {
  items: NotificationView[];
  unread_count: number;
};

export type NewNotification = {
  userId: number;
  kind: string;
  contentClass: ContentClass;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  /// Send it only once, however many times the caller asks. The renewal sweep leans on this.
  dedupeKey?: string;
  /// Also email it, when the account has an address. Phone-only accounts simply do not.
  alsoEmail?: boolean;
};

/// The most a list returns at once. A year of renewal notices is not a feed to scroll.
export const MAX_NOTIFICATIONS = 50;

/// In-app messages (docs/13 §5, docs/14 §6). No push: a phone that has the app open reads the list,
/// and the renewal notices docs/11 §8 requires reach an email as well when there is one.
@Injectable()
export class NotificationsService {
  constructor(
    @InjectRepository(NotificationEntity)
    private readonly notifications: Repository<NotificationEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly mail: MailService,
  ) {}

  /// Returns the row, or null when [NewNotification.dedupeKey] says it has already been sent.
  async notify(input: NewNotification): Promise<NotificationEntity | null> {
    if (!CONTENT_CLASSES.includes(input.contentClass)) {
      throw new Error(`Unknown content class: ${input.contentClass}`);
    }

    let saved: NotificationEntity;
    try {
      saved = await this.notifications.save(
        this.notifications.create({
          userId: input.userId,
          kind: input.kind,
          contentClass: input.contentClass,
          title: input.title,
          body: input.body,
          data: input.data ?? null,
          dedupeKey: input.dedupeKey ?? null,
        }),
      );
    } catch (error) {
      // The unique index refused it: this exact notice is already in the list.
      if (
        error instanceof QueryFailedError &&
        (error.driverError as { code?: string })?.code === '23505'
      ) {
        return null;
      }
      throw error;
    }

    if (input.alsoEmail) await this.email(input);
    return saved;
  }

  /// Newest first. [before] pages backwards by `created_at`.
  async list(
    userId: number,
    options: { limit?: number; before?: string } = {},
  ): Promise<NotificationListView> {
    const limit = Math.min(
      options.limit ?? MAX_NOTIFICATIONS,
      MAX_NOTIFICATIONS,
    );
    const before = options.before ? new Date(options.before) : null;

    const [items, unread] = await Promise.all([
      this.notifications.find({
        where:
          before && !Number.isNaN(before.getTime())
            ? { userId, createdAt: LessThan(before) }
            : { userId },
        order: { createdAt: 'DESC' },
        take: limit,
      }),
      this.notifications.count({ where: { userId, readAt: IsNull() } }),
    ]);

    return {
      items: items.map((row) => this.toView(row)),
      unread_count: unread,
    };
  }

  /// Marking something already read is not an error — two taps are one intention.
  async markRead(userId: number, id: string): Promise<void> {
    await this.notifications.update(
      { id, userId, readAt: IsNull() },
      { readAt: new Date() },
    );
  }

  async markAllRead(userId: number): Promise<void> {
    await this.notifications.update(
      { userId, readAt: IsNull() },
      { readAt: new Date() },
    );
  }

  /// Never fails the notification it belongs to: the list is the channel that must work, and a
  /// mail server that is down is not a reason to lose the notice.
  private async email(input: NewNotification): Promise<void> {
    try {
      const user = await this.users.findOne({ where: { id: input.userId } });
      if (!user?.email) return;
      await this.mail.notification({
        to: user.email,
        data: { title: input.title, body: input.body },
      });
    } catch {
      // Swallowed on purpose. No log line either: rule 5 keeps addresses out of the logs.
    }
  }

  private toView(row: NotificationEntity): NotificationView {
    return {
      id: row.id,
      kind: row.kind,
      content_class: row.contentClass,
      title: row.title,
      body: row.body,
      data: row.data,
      read_at: row.readAt?.toISOString() ?? null,
      created_at: row.createdAt.toISOString(),
    };
  }
}
