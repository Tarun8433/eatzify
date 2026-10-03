import {
  ConflictException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, IsNull, LessThanOrEqual, Not, Repository } from 'typeorm';
import {
  NotificationCampaignEntity,
  type CampaignSegment,
  type Channel,
  type ChannelResult,
} from '../campaigns/entities/notification-campaign.entity';
import { PushService } from '../campaigns/push.service';
import type { ContentClass } from '../notifications/entities/notification.entity';
import { NotificationEntity } from '../notifications/entities/notification.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { AdminAudienceService } from './admin-audience.service';
import type { Actor } from './admin-users.service';
import { AuditService } from './audit.service';

export type CampaignView = {
  id: string;
  title: string;
  body: string;
  content_class: ContentClass;
  segment: CampaignSegment;
  channels: Channel[];
  status: NotificationCampaignEntity['status'];
  scheduled_at: string;
  sent_at: string | null;
  audience: number | null;
  results: Partial<Record<Channel, ChannelResult>>;
  /// In-app messages from this campaign that have been opened.
  read: number;
  error: string | null;
  created_by: number;
  created_at: string;
};

export type CampaignInput = {
  title: string;
  body: string;
  content_class: ContentClass;
  segment: CampaignSegment;
  channels: Channel[];
  /// Absent: send now.
  scheduled_at?: string;
};

/// Admin panel plan, Phase C: messages to many people, now or later, over in-app, email and push.
/// SMS and WhatsApp are listed but refused until their providers are set up.
@Injectable()
export class AdminCampaignsService {
  private readonly log = new Logger(AdminCampaignsService.name);

  constructor(
    @InjectRepository(NotificationCampaignEntity)
    private readonly campaigns: Repository<NotificationCampaignEntity>,
    @InjectRepository(NotificationEntity)
    private readonly notifications: Repository<NotificationEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly audience: AdminAudienceService,
    private readonly notify: NotificationsService,
    private readonly push: PushService,
    private readonly audit: AuditService,
  ) {}

  /// Which channels can actually deliver today.
  channels(): Record<Channel, boolean> {
    return {
      in_app: true,
      email: true,
      push: this.push.configured,
      sms: false,
      whatsapp: false,
    };
  }

  async preview(
    segment: CampaignSegment,
    contentClass: ContentClass,
    now = new Date(),
  ): Promise<{ count: number }> {
    const ids = await this.audience.idsFor(segment, contentClass, now);
    return { count: ids.length };
  }

  async create(
    input: CampaignInput,
    actor: Actor,
    now = new Date(),
  ): Promise<CampaignView> {
    const available = this.channels();
    const off = input.channels.filter((c) => !available[c]);
    if (off.length) {
      throw this.unprocessable(
        'CHANNEL_NOT_CONFIGURED',
        `Not set up yet: ${off.join(', ')}. Choose another channel.`,
      );
    }
    // In-app is the record of what was sent; every campaign has it.
    const channels = [...new Set<Channel>(['in_app', ...input.channels])];
    const scheduledAt = input.scheduled_at ? new Date(input.scheduled_at) : now;
    if (scheduledAt.getTime() < now.getTime() - 60_000) {
      throw this.unprocessable(
        'SCHEDULE_IN_PAST',
        'Pick a time in the future.',
      );
    }
    // Checked now, so a segment that breaks a rule is refused at once, not at 3 a.m.
    await this.audience.idsFor(input.segment, input.content_class, now);

    let row = await this.campaigns.save(
      this.campaigns.create({
        title: input.title.trim(),
        body: input.body.trim(),
        contentClass: input.content_class,
        segment: input.segment,
        channels,
        scheduledAt,
        createdBy: actor.userId,
      }),
    );
    await this.audit.record({
      actorUserId: actor.userId,
      actorRole: String(actor.roleId),
      action: 'notification_send',
      resource: 'notification_campaign',
      meta: {
        campaign_id: row.id,
        channels,
        content_class: input.content_class,
        scheduled_at: scheduledAt.toISOString(),
        by_condition: (input.segment.conditions?.length ?? 0) > 0,
      },
      ip: actor.ip ?? null,
    });

    if (scheduledAt.getTime() <= now.getTime()) row = await this.run(row, now);
    return (await this.views([row]))[0];
  }

  async list(limit = 50): Promise<CampaignView[]> {
    const rows = await this.campaigns.find({
      order: { createdAt: 'DESC' },
      take: Math.min(limit, 200),
    });
    return this.views(rows);
  }

  async cancel(id: string, actor: Actor): Promise<CampaignView> {
    const row = await this.campaigns.findOne({ where: { id } });
    if (!row) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'CAMPAIGN_NOT_FOUND', user_message: 'No such message.' },
      });
    }
    if (row.status !== 'scheduled') {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: {
          code: 'CAMPAIGN_NOT_SCHEDULED',
          user_message: 'Only a scheduled message can be cancelled.',
        },
      });
    }
    row.status = 'cancelled';
    await this.campaigns.save(row);
    await this.audit.record({
      actorUserId: actor.userId,
      actorRole: String(actor.roleId),
      action: 'campaign_cancel',
      resource: 'notification_campaign',
      meta: { campaign_id: id },
      ip: actor.ip ?? null,
    });
    return (await this.views([row]))[0];
  }

  /// Sends whatever has come due; `CampaignScheduler` calls it every minute.
  async runDue(now = new Date()): Promise<number> {
    const due = await this.campaigns.find({
      where: { status: 'scheduled', scheduledAt: LessThanOrEqual(now) },
      take: 20,
    });
    for (const row of due) await this.run(row, now);
    return due.length;
  }

  /// Sends one campaign. The status moves to `sending` first, guarded on `scheduled`, so two
  /// servers (or a slow minute) never send the same campaign twice.
  private async run(
    row: NotificationCampaignEntity,
    now: Date,
  ): Promise<NotificationCampaignEntity> {
    const claimed = await this.campaigns.update(
      { id: row.id, status: 'scheduled' },
      { status: 'sending' },
    );
    if (!claimed.affected) return row;

    try {
      const ids = await this.audience.idsFor(
        row.segment,
        row.contentClass,
        now,
      );
      const results: Partial<Record<Channel, ChannelResult>> = {};
      const withEmail = row.channels.includes('email');

      let inApp = 0;
      for (const userId of ids) {
        const saved = await this.notify.notify({
          userId,
          kind: 'admin_broadcast',
          contentClass: row.contentClass,
          title: row.title,
          body: row.body,
          data: { campaign_id: row.id },
          dedupeKey: `campaign:${row.id}`,
          alsoEmail: withEmail,
        });
        if (saved) inApp++;
      }
      results.in_app = { sent: inApp, failed: 0 };
      if (withEmail) {
        const reachable = ids.length
          ? await this.users.count({
              where: { id: In(ids), email: Not(IsNull()) },
            })
          : 0;
        // Email goes with the in-app row; accounts without an address are skipped by the mailer.
        results.email = { sent: reachable, failed: 0 };
      }
      if (row.channels.includes('push')) {
        results.push = await this.push.sendToUsers(ids, row.title, row.body, {
          campaign_id: row.id,
        });
      }

      Object.assign(row, {
        status: 'sent',
        sentAt: new Date(),
        audience: ids.length,
        results,
      });
    } catch (e) {
      const message = e instanceof Error ? e.message : 'unknown error';
      this.log.error(`campaign ${row.id} failed: ${message}`);
      Object.assign(row, { status: 'failed', error: message.slice(0, 500) });
    }
    return this.campaigns.save(row);
  }

  private async views(
    rows: NotificationCampaignEntity[],
  ): Promise<CampaignView[]> {
    const ids = rows.map((r) => r.id);
    const reads = ids.length
      ? await this.notifications
          .createQueryBuilder('n')
          .select(`n.data->>'campaign_id'`, 'cid')
          .addSelect('COUNT(*)', 'n')
          .where(`n.data->>'campaign_id' IN (:...ids)`, { ids })
          .andWhere('n."readAt" IS NOT NULL')
          .groupBy('cid')
          .getRawMany<{ cid: string; n: string }>()
      : [];
    const readBy = new Map(reads.map((r) => [r.cid, Number(r.n)]));
    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      body: r.body,
      content_class: r.contentClass,
      segment: r.segment,
      channels: r.channels,
      status: r.status,
      scheduled_at: r.scheduledAt.toISOString(),
      sent_at: r.sentAt?.toISOString() ?? null,
      audience: r.audience,
      results: r.results,
      read: readBy.get(r.id) ?? 0,
      error: r.error,
      created_by: r.createdBy,
      created_at: r.createdAt.toISOString(),
    }));
  }

  private unprocessable(code: string, message: string) {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: message },
    });
  }
}
