import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PaymentOrderEntity } from '../billing/entities/payment-order.entity';
import { NotificationEntity } from '../notifications/entities/notification.entity';
import { StatusEnum } from '../statuses/statuses.enum';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { AuditLogEntity } from './entities/audit-log.entity';

/// The calendar day a person in India means by "today". Not the 04:00 diary boundary — that is
/// for food logs (api rule 4); a dashboard counts calendar days.
const IST = 'Asia/Kolkata';
const IST_OFFSET_MS = 330 * 60_000;
const DAY_MS = 86_400_000;
export const MAX_SERIES_DAYS = 366;

export const SERIES_METRICS = [
  'signups',
  'payments_paid',
  'payments_failed',
  'refunds',
] as const;
export type SeriesMetric = (typeof SERIES_METRICS)[number];

export type DashboardToday = {
  users: {
    total: number;
    new_today: number;
    pending_verification: number;
    blocked: number;
  };
  payments: {
    orders_today: number;
    paid_today: number;
    revenue_today_paise: string;
    failed_today: number;
    refunds_today: number;
  };
  notifications_today: number;
  recent_activity: {
    at: string;
    actor_user_id: number | null;
    action: string;
    resource: string;
    subject_user_id: number | null;
  }[];
};

export type SeriesPoint = { day: string; count: number; amount_paise: string };

/// Midnight today in India, as an instant.
export function istDayStart(now: Date): Date {
  const shifted = now.getTime() + IST_OFFSET_MS;
  return new Date(shifted - (shifted % DAY_MS) - IST_OFFSET_MS);
}

/// Admin panel plan, Phase A: the dashboard's top cards, its activity feed and its charts.
/// Demo users are left out of every figure (database rules).
@Injectable()
export class AdminDashboardService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    @InjectRepository(NotificationEntity)
    private readonly notifications: Repository<NotificationEntity>,
    @InjectRepository(AuditLogEntity)
    private readonly audit: Repository<AuditLogEntity>,
  ) {}

  async today(now = new Date()): Promise<DashboardToday> {
    const since = istDayStart(now);
    const realUsers = () =>
      this.users.createQueryBuilder('u').where('u."isDemo" = false');
    const realOrders = () =>
      this.orders
        .createQueryBuilder('o')
        .innerJoin(UserEntity, 'u', 'u.id = o."userId" AND u."isDemo" = false');

    const [
      total,
      newToday,
      pending,
      blocked,
      ordersToday,
      paid,
      failedToday,
      refundsToday,
      notificationsToday,
      recent,
    ] = await Promise.all([
      realUsers().getCount(),
      realUsers().andWhere('u."createdAt" >= :since', { since }).getCount(),
      realUsers()
        .andWhere('u."statusId" = :s', { s: StatusEnum.inactive })
        .getCount(),
      realUsers()
        .andWhere('u."statusId" = :s', { s: StatusEnum.blocked })
        .getCount(),
      realOrders().where('o."createdAt" >= :since', { since }).getCount(),
      realOrders()
        .select('COUNT(*)', 'n')
        .addSelect('COALESCE(SUM(o."amountPaise"), 0)', 'sum')
        .where('o."paidAt" >= :since', { since })
        .andWhere(`o.status IN ('paid', 'refunded')`)
        .getRawOne<{ n: string; sum: string }>(),
      realOrders()
        .where('o."createdAt" >= :since', { since })
        .andWhere(`o.status = 'failed'`)
        .getCount(),
      realOrders().where('o."refundedAt" >= :since', { since }).getCount(),
      this.notifications
        .createQueryBuilder('n')
        .where('n."createdAt" >= :since', { since })
        .getCount(),
      this.audit.find({ order: { createdAt: 'DESC' }, take: 10 }),
    ]);

    return {
      users: {
        total,
        new_today: newToday,
        pending_verification: pending,
        blocked,
      },
      payments: {
        orders_today: ordersToday,
        paid_today: Number(paid?.n ?? 0),
        revenue_today_paise: String(paid?.sum ?? '0'),
        failed_today: failedToday,
        refunds_today: refundsToday,
      },
      notifications_today: notificationsToday,
      recent_activity: recent.map((a) => ({
        at: a.createdAt.toISOString(),
        actor_user_id: a.actorUserId,
        action: a.action,
        resource: a.resource,
        subject_user_id: a.subjectUserId,
      })),
    };
  }

  /// One point per Indian calendar day in [from, to], zero-filled so a chart has no gaps.
  async series(
    metric: SeriesMetric,
    from: Date,
    to: Date,
  ): Promise<SeriesPoint[]> {
    const start = istDayStart(from);
    const days = Math.min(
      Math.floor((istDayStart(to).getTime() - start.getTime()) / DAY_MS) + 1,
      MAX_SERIES_DAYS,
    );
    const end = new Date(start.getTime() + days * DAY_MS);
    const rows = await this.raw(metric, start, end);
    const byDay = new Map(rows.map((r) => [r.day, r]));

    return Array.from({ length: Math.max(days, 0) }, (_, i) => {
      const day = new Date(start.getTime() + i * DAY_MS + IST_OFFSET_MS)
        .toISOString()
        .slice(0, 10);
      const hit = byDay.get(day);
      return {
        day,
        count: Number(hit?.n ?? 0),
        amount_paise: String(hit?.sum ?? '0'),
      };
    });
  }

  private raw(
    metric: SeriesMetric,
    start: Date,
    end: Date,
  ): Promise<{ day: string; n: string; sum: string }[]> {
    const dayOf = (column: string) =>
      `to_char(${column} AT TIME ZONE '${IST}', 'YYYY-MM-DD')`;

    if (metric === 'signups') {
      return this.users
        .createQueryBuilder('u')
        .select(dayOf('u."createdAt"'), 'day')
        .addSelect('COUNT(*)', 'n')
        .addSelect('0', 'sum')
        .where('u."isDemo" = false')
        .andWhere('u."createdAt" >= :start AND u."createdAt" < :end', {
          start,
          end,
        })
        .groupBy('day')
        .getRawMany();
    }

    const column = {
      payments_paid: 'o."paidAt"',
      payments_failed: 'o."createdAt"',
      refunds: 'o."refundedAt"',
    }[metric];
    const q = this.orders
      .createQueryBuilder('o')
      .innerJoin(UserEntity, 'u', 'u.id = o."userId" AND u."isDemo" = false')
      .select(dayOf(column), 'day')
      .addSelect('COUNT(*)', 'n')
      .addSelect('COALESCE(SUM(o."amountPaise"), 0)', 'sum')
      .where(`${column} >= :start AND ${column} < :end`, { start, end })
      .groupBy('day');
    if (metric === 'payments_paid')
      q.andWhere(`o.status IN ('paid', 'refunded')`);
    if (metric === 'payments_failed') q.andWhere(`o.status = 'failed'`);
    return q.getRawMany();
  }
}
