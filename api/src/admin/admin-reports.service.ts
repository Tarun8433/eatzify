import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Between, Repository } from 'typeorm';
import { PaymentOrderEntity } from '../billing/entities/payment-order.entity';
import { NotificationCampaignEntity } from '../campaigns/entities/notification-campaign.entity';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import { UserActivityDayEntity } from '../users/infrastructure/persistence/relational/entities/user-activity-day.entity';
import { UserBlockEntity } from '../users/infrastructure/persistence/relational/entities/user-block.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';

export const REPORT_KINDS = [
  'users',
  'payments',
  'verification',
  'notifications',
  'offers',
] as const;
export type ReportKind = (typeof REPORT_KINDS)[number];

/// A report is a table: the column names, then rows of plain values. Aggregates only — no name,
/// email or phone ever appears in one (docs/10: bulk personal-data export is a separate thing).
export type Report = {
  kind: ReportKind;
  from: string;
  to: string;
  columns: string[];
  rows: (string | number)[][];
};

export type Analytics = {
  dau_today: number;
  mau: number;
  /// Of people who signed up 7 to 37 days ago, the share who came back 7 or more days later.
  retention_d7: number | null;
  payment_success_rate: number | null;
  refund_rate: number | null;
  dau: { day: string; count: number }[];
};

const IST = 'Asia/Kolkata';
const DAY_MS = 86_400_000;
const IST_OFFSET_MS = 330 * 60_000;
export const MAX_REPORT_DAYS = 366;

function istDay(at: Date): string {
  return new Date(at.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

/// RFC 4180: quote every field, double any quote inside it.
export function toCsv(report: Report): string {
  const cell = (v: string | number) => `"${String(v).replace(/"/g, '""')}"`;
  return (
    [report.columns, ...report.rows]
      .map((r) => r.map(cell).join(','))
      .join('\r\n') + '\r\n'
  );
}

/// Admin panel plan, Phase D: reports by date range, and the analytics page. Demo users are left
/// out of every figure (database rules).
@Injectable()
export class AdminReportsService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(UserBlockEntity)
    private readonly blocks: Repository<UserBlockEntity>,
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    @InjectRepository(NotificationCampaignEntity)
    private readonly campaigns: Repository<NotificationCampaignEntity>,
    @InjectRepository(UserActivityDayEntity)
    private readonly activity: Repository<UserActivityDayEntity>,
  ) {}

  async report(kind: ReportKind, from: Date, to: Date): Promise<Report> {
    const end = new Date(
      Math.min(to.getTime(), from.getTime() + MAX_REPORT_DAYS * DAY_MS),
    );
    const head = { kind, from: from.toISOString(), to: end.toISOString() };
    switch (kind) {
      case 'users':
        return { ...head, ...(await this.usersReport(from, end)) };
      case 'payments':
        return { ...head, ...(await this.paymentsReport(from, end)) };
      case 'verification':
        return { ...head, ...(await this.verificationReport(from, end)) };
      case 'notifications':
        return { ...head, ...(await this.notificationsReport(from, end)) };
      case 'offers':
        return { ...head, ...(await this.offersReport(from, end)) };
    }
  }

  async analytics(now = new Date()): Promise<Analytics> {
    const today = istDay(now);
    const monthAgo = istDay(new Date(now.getTime() - 29 * DAY_MS));
    const [dauToday, mau, dau, retention, rates] = await Promise.all([
      this.activity.count({ where: { day: today } }),
      this.activity
        .createQueryBuilder('a')
        .select('COUNT(DISTINCT a."userId")', 'n')
        .where('a.day >= :from', { from: monthAgo })
        .getRawOne<{ n: string }>(),
      this.activity
        .createQueryBuilder('a')
        .select(`to_char(a.day, 'YYYY-MM-DD')`, 'day')
        .addSelect('COUNT(*)', 'n')
        .where('a.day >= :from', { from: monthAgo })
        .groupBy('a.day')
        .orderBy('a.day')
        .getRawMany<{ day: string; n: string }>(),
      this.retention(now),
      this.orders
        .createQueryBuilder('o')
        .innerJoin(UserEntity, 'u', 'u.id = o."userId" AND u."isDemo" = false')
        .select(
          `COUNT(*) FILTER (WHERE o.status IN ('paid', 'refunded'))`,
          'paid',
        )
        .addSelect(`COUNT(*) FILTER (WHERE o.status = 'failed')`, 'failed')
        .addSelect(`COUNT(*) FILTER (WHERE o.status = 'refunded')`, 'refunded')
        .where('o."createdAt" >= :since', {
          since: new Date(now.getTime() - 30 * DAY_MS),
        })
        .getRawOne<{ paid: string; failed: string; refunded: string }>(),
    ]);
    const paid = Number(rates?.paid ?? 0);
    const failed = Number(rates?.failed ?? 0);
    const byDay = new Map(dau.map((d) => [d.day, Number(d.n)]));
    return {
      dau_today: dauToday,
      mau: Number(mau?.n ?? 0),
      retention_d7: retention,
      payment_success_rate: paid + failed ? paid / (paid + failed) : null,
      refund_rate: paid ? Number(rates?.refunded ?? 0) / paid : null,
      dau: Array.from({ length: 30 }, (_, i) => {
        const day = istDay(new Date(now.getTime() - (29 - i) * DAY_MS));
        return { day, count: byDay.get(day) ?? 0 };
      }),
    };
  }

  private async retention(now: Date): Promise<number | null> {
    const row = await this.users
      .createQueryBuilder('u')
      .select('COUNT(*)', 'cohort')
      .addSelect(
        `COUNT(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM user_activity_day a
          WHERE a."userId" = u.id
            AND a.day >= (u."createdAt" AT TIME ZONE '${IST}')::date + 7))`,
        'returned',
      )
      .where('u."isDemo" = false')
      .andWhere('u."createdAt" BETWEEN :from AND :to', {
        from: new Date(now.getTime() - 37 * DAY_MS),
        to: new Date(now.getTime() - 7 * DAY_MS),
      })
      .getRawOne<{ cohort: string; returned: string }>();
    const cohort = Number(row?.cohort ?? 0);
    return cohort ? Number(row?.returned ?? 0) / cohort : null;
  }

  private dayOf(column: string): string {
    return `to_char(${column} AT TIME ZONE '${IST}', 'YYYY-MM-DD')`;
  }

  private async usersReport(from: Date, to: Date) {
    const [signups, blocks, active] = await Promise.all([
      this.users
        .createQueryBuilder('u')
        .select(this.dayOf('u."createdAt"'), 'day')
        .addSelect('COUNT(*)', 'signups')
        .addSelect(`COUNT(*) FILTER (WHERE u."statusId" = 1)`, 'verified')
        .addSelect(`COUNT(*) FILTER (WHERE u."statusId" = 2)`, 'unverified')
        .where('u."isDemo" = false')
        .andWhere('u."createdAt" BETWEEN :from AND :to', { from, to })
        .groupBy('day')
        .getRawMany<{
          day: string;
          signups: string;
          verified: string;
          unverified: string;
        }>(),
      this.blocks
        .createQueryBuilder('b')
        .select(this.dayOf('b."blockedAt"'), 'day')
        .addSelect('COUNT(*)', 'n')
        .where('b."blockedAt" BETWEEN :from AND :to', { from, to })
        .groupBy('day')
        .getRawMany<{ day: string; n: string }>(),
      this.activity
        .createQueryBuilder('a')
        .select(`to_char(a.day, 'YYYY-MM-DD')`, 'day')
        .addSelect('COUNT(*)', 'n')
        .where('a.day BETWEEN :from AND :to', {
          from: istDay(from),
          to: istDay(to),
        })
        .groupBy('a.day')
        .getRawMany<{ day: string; n: string }>(),
    ]);
    const s = new Map(signups.map((r) => [r.day, r]));
    const b = new Map(blocks.map((r) => [r.day, Number(r.n)]));
    const a = new Map(active.map((r) => [r.day, Number(r.n)]));
    return {
      columns: [
        'day',
        'new_users',
        'verified_now',
        'unverified_now',
        'blocked',
        'active_users',
      ],
      rows: this.days(from, to).map((day) => [
        day,
        Number(s.get(day)?.signups ?? 0),
        Number(s.get(day)?.verified ?? 0),
        Number(s.get(day)?.unverified ?? 0),
        b.get(day) ?? 0,
        a.get(day) ?? 0,
      ]),
    };
  }

  private async paymentsReport(from: Date, to: Date) {
    const rows = await this.orders
      .createQueryBuilder('o')
      .innerJoin(UserEntity, 'u', 'u.id = o."userId" AND u."isDemo" = false')
      .select(this.dayOf('o."createdAt"'), 'day')
      .addSelect(
        `COUNT(*) FILTER (WHERE o.status IN ('paid', 'refunded'))`,
        'paid',
      )
      .addSelect(
        `COALESCE(SUM(o."amountPaise") FILTER (WHERE o.status IN ('paid', 'refunded')), 0)`,
        'collected',
      )
      .addSelect(`COUNT(*) FILTER (WHERE o.status = 'failed')`, 'failed')
      .addSelect(`COUNT(*) FILTER (WHERE o.status = 'created')`, 'pending')
      .addSelect(`COUNT(*) FILTER (WHERE o.status = 'refunded')`, 'refunded')
      .addSelect(
        `COALESCE(SUM(o."amountPaise") FILTER (WHERE o.status = 'refunded'), 0)`,
        'refunded_amount',
      )
      .where('o."createdAt" BETWEEN :from AND :to', { from, to })
      .groupBy('day')
      .getRawMany<Record<string, string>>();
    const by = new Map(rows.map((r) => [r.day, r]));
    const rupees = (paise: string | undefined) =>
      (Number(paise ?? 0) / 100).toFixed(2);
    return {
      columns: [
        'day',
        'paid_orders',
        'collected_inr',
        'failed',
        'pending',
        'refunded_orders',
        'refunded_inr',
        'net_inr',
      ],
      rows: this.days(from, to).map((day) => {
        const r = by.get(day);
        const net = Number(r?.collected ?? 0) - Number(r?.refunded_amount ?? 0);
        return [
          day,
          Number(r?.paid ?? 0),
          rupees(r?.collected),
          Number(r?.failed ?? 0),
          Number(r?.pending ?? 0),
          Number(r?.refunded ?? 0),
          rupees(r?.refunded_amount),
          (net / 100).toFixed(2),
        ];
      }),
    };
  }

  private async verificationReport(from: Date, to: Date) {
    const rows = await this.applications
      .createQueryBuilder('a')
      .select('a.status', 'status')
      .addSelect('COUNT(*)', 'n')
      .where('a."updatedAt" BETWEEN :from AND :to', { from, to })
      .groupBy('a.status')
      .getRawMany<{ status: string; n: string }>();
    const unconfirmed = await this.users.count({
      where: { status: { id: 2 }, isDemo: false, createdAt: Between(from, to) },
    });
    return {
      columns: ['item', 'count'],
      rows: [
        ...rows.map((r) => [`coach_applications_${r.status}`, Number(r.n)]),
        ['emails_still_unconfirmed', unconfirmed],
      ],
    };
  }

  private async notificationsReport(from: Date, to: Date) {
    const rows = await this.campaigns.find({
      where: { createdAt: Between(from, to) },
      order: { createdAt: 'ASC' },
    });
    return {
      columns: [
        'sent_at',
        'title',
        'kind',
        'status',
        'audience',
        'in_app',
        'email',
        'push',
        'push_failed',
      ],
      rows: rows.map((c) => [
        (c.sentAt ?? c.scheduledAt).toISOString(),
        c.title,
        c.contentClass,
        c.status,
        c.audience ?? 0,
        c.results.in_app?.sent ?? 0,
        c.results.email?.sent ?? 0,
        c.results.push?.sent ?? 0,
        c.results.push?.failed ?? 0,
      ]),
    };
  }

  private async offersReport(from: Date, to: Date) {
    const rows = await this.orders
      .createQueryBuilder('o')
      .select('o."couponCode"', 'code')
      .addSelect(
        `COUNT(*) FILTER (WHERE o.status IN ('paid', 'refunded'))`,
        'used',
      )
      .addSelect(`COUNT(*)`, 'tried')
      .addSelect(
        `COALESCE(SUM(o."amountPaise") FILTER (WHERE o.status IN ('paid', 'refunded')), 0)`,
        'revenue',
      )
      .addSelect(
        `COALESCE(SUM(o."discountPaise") FILTER (WHERE o.status IN ('paid', 'refunded')), 0)`,
        'discount',
      )
      .where('o."couponCode" IS NOT NULL')
      .andWhere('o."createdAt" BETWEEN :from AND :to', { from, to })
      .groupBy('o."couponCode"')
      .getRawMany<Record<string, string>>();
    return {
      columns: [
        'code',
        'checkouts_started',
        'paid',
        'conversion',
        'revenue_inr',
        'discount_inr',
      ],
      rows: rows.map((r) => [
        r.code,
        Number(r.tried),
        Number(r.used),
        Number(r.tried)
          ? (Number(r.used) / Number(r.tried)).toFixed(2)
          : '0.00',
        (Number(r.revenue) / 100).toFixed(2),
        (Number(r.discount) / 100).toFixed(2),
      ]),
    };
  }

  /// Every Indian calendar day from [from] to [to], so a report has a row for each, zero or not.
  private days(from: Date, to: Date): string[] {
    const out: string[] = [];
    for (
      let t = from.getTime();
      istDay(new Date(t)) <= istDay(to) && out.length <= MAX_REPORT_DAYS;
      t += DAY_MS
    ) {
      out.push(istDay(new Date(t)));
    }
    return [...new Set(out)];
  }
}
