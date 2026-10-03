import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import {
  PaymentOrderEntity,
  type OrderStatus,
} from '../billing/entities/payment-order.entity';
import { RefundRequestEntity } from '../billing/entities/refund-request.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { istDayStart } from './admin-dashboard.service';
import { maskPhone } from './admin-clients.service';
import { maskEmail, type Actor } from './admin-users.service';
import { AuditService } from './audit.service';

export const MAX_PAYMENTS_PAGE = 100;

export type PaymentRow = {
  order_id: string;
  user_id: number;
  user_name: string;
  email?: string | null;
  email_masked: string | null;
  amount_paise: string;
  discount_paise: string;
  coupon: string | null;
  plan: string;
  kind: string;
  /// `created` is shown as "pending": started at the gateway, never finished.
  status: OrderStatus;
  gateway: 'cashfree';
  via_play_choice: boolean;
  failure_reason: string | null;
  created_at: string;
  paid_at: string | null;
  refunded_at: string | null;
};

export type PaymentDetail = PaymentRow & {
  phone_masked: string | null;
  refund_requests: {
    id: string;
    status: string;
    reason: string;
    created_at: string;
  }[];
  subscription: { tier: string; status: string; ends_at: string | null } | null;
};

export type PaymentSummary = {
  by_status: Record<OrderStatus, { count: number; amount_paise: string }>;
  today: { orders: number; collected_paise: string; failed: number };
  failure_reasons: { reason: string; count: number }[];
  refund_requests_open: number;
  store_subscriptions: { play: number; app_store: number };
};

/// Admin panel plan, Phase B: what people paid through Cashfree, what failed and why. Play and
/// App Store money is the store's own (refunds included); only their live plans are counted here.
/// Demo users are left out of the figures, not out of the list.
@Injectable()
export class AdminPaymentsService {
  constructor(
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(RefundRequestEntity)
    private readonly requests: Repository<RefundRequestEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    private readonly notifications: NotificationsService,
    private readonly audit: AuditService,
  ) {}

  /// Newest first, keyset-paged on creation time (the cursor is the last row's `created_at`).
  async list(filter: {
    status?: OrderStatus;
    userId?: number;
    from?: Date;
    to?: Date;
    cursor?: Date;
    limit?: number;
  }): Promise<{ rows: PaymentRow[]; next_cursor: string | null }> {
    const limit = Math.min(Math.max(filter.limit ?? 50, 1), MAX_PAYMENTS_PAGE);
    const q = this.orders
      .createQueryBuilder('o')
      .orderBy('o.createdAt', 'DESC')
      .take(limit + 1);
    if (filter.status)
      q.andWhere('o.status = :status', { status: filter.status });
    if (filter.userId)
      q.andWhere('o.userId = :userId', { userId: filter.userId });
    if (filter.from) q.andWhere('o.createdAt >= :from', { from: filter.from });
    if (filter.to) q.andWhere('o.createdAt <= :to', { to: filter.to });
    if (filter.cursor)
      q.andWhere('o.createdAt < :cursor', { cursor: filter.cursor });

    const found = await q.getMany();
    const page = found.slice(0, limit);
    const people = await this.people(page.map((o) => o.userId));
    return {
      rows: page.map((o) => this.row(o, people.get(o.userId))),
      next_cursor:
        found.length > limit
          ? page[page.length - 1].createdAt.toISOString()
          : null,
    };
  }

  async detail(cashfreeOrderId: string): Promise<PaymentDetail> {
    const order = await this.find(cashfreeOrderId);
    const [people, requests, sub] = await Promise.all([
      this.people([order.userId]),
      this.requests.find({
        where: { orderId: order.id },
        order: { createdAt: 'DESC' },
      }),
      this.subscriptions.findOne({
        where: { userId: order.userId, providerRef: order.cashfreeOrderId },
      }),
    ]);
    const person = people.get(order.userId);
    return {
      ...this.row(order, person),
      phone_masked: maskPhone(person?.phone ?? null),
      refund_requests: requests.map((r) => ({
        id: r.id,
        status: r.status,
        reason: r.reason,
        created_at: r.createdAt.toISOString(),
      })),
      subscription: sub
        ? {
            tier: sub.tier,
            status: sub.status,
            ends_at: sub.currentPeriodEnd?.toISOString() ?? null,
          }
        : null,
    };
  }

  async summary(now = new Date()): Promise<PaymentSummary> {
    const since = istDayStart(now);
    const real = () =>
      this.orders
        .createQueryBuilder('o')
        .innerJoin(UserEntity, 'u', 'u.id = o."userId" AND u."isDemo" = false');

    const [byStatus, today, failed, reasons, open, store] = await Promise.all([
      real()
        .select('o.status', 'status')
        .addSelect('COUNT(*)', 'n')
        .addSelect('COALESCE(SUM(o."amountPaise"), 0)', 'sum')
        .groupBy('o.status')
        .getRawMany<{ status: OrderStatus; n: string; sum: string }>(),
      real()
        .select('COUNT(*)', 'n')
        .addSelect('COALESCE(SUM(o."amountPaise"), 0)', 'sum')
        .where('o."paidAt" >= :since', { since })
        .andWhere(`o.status IN ('paid', 'refunded')`)
        .getRawOne<{ n: string; sum: string }>(),
      real()
        .where('o."createdAt" >= :since', { since })
        .andWhere(`o.status = 'failed'`)
        .getCount(),
      real()
        .select(`COALESCE(o."failureReason", 'Unknown')`, 'reason')
        .addSelect('COUNT(*)', 'n')
        .where(`o.status = 'failed'`)
        .groupBy('reason')
        .orderBy('n', 'DESC')
        .limit(10)
        .getRawMany<{ reason: string; n: string }>(),
      this.requests.count({ where: { status: 'requested' } }),
      this.subscriptions
        .createQueryBuilder('s')
        .select('s.provider', 'provider')
        .addSelect('COUNT(*)', 'n')
        .where(`s.provider IN ('play', 'app_store')`)
        .andWhere(`s.status IN ('trialing', 'active', 'grace', 'past_due')`)
        .groupBy('s.provider')
        .getRawMany<{ provider: string; n: string }>(),
    ]);

    const zero = { count: 0, amount_paise: '0' };
    const by: PaymentSummary['by_status'] = {
      created: { ...zero },
      paid: { ...zero },
      failed: { ...zero },
      refunded: { ...zero },
    };
    for (const r of byStatus) {
      by[r.status] = { count: Number(r.n), amount_paise: String(r.sum) };
    }
    const storeBy = new Map(store.map((s) => [s.provider, Number(s.n)]));
    return {
      by_status: by,
      today: {
        orders: Number(today?.n ?? 0),
        collected_paise: String(today?.sum ?? '0'),
        failed,
      },
      failure_reasons: reasons.map((r) => ({
        reason: r.reason,
        count: Number(r.n),
      })),
      refund_requests_open: open,
      store_subscriptions: {
        play: storeBy.get('play') ?? 0,
        app_store: storeBy.get('app_store') ?? 0,
      },
    };
  }

  /// A nudge to someone whose payment did not finish: in the app and by email, at most once a day
  /// per order (the dedupe key carries the date).
  async remind(
    cashfreeOrderId: string,
    actor: Actor,
    now = new Date(),
  ): Promise<void> {
    const order = await this.find(cashfreeOrderId);
    await this.notifications.notify({
      userId: order.userId,
      kind: 'payment_retry',
      contentClass: 'service',
      title: 'Your payment did not go through',
      body: 'Nothing was charged. You can try again any time from the Plans screen.',
      data: { order_id: order.cashfreeOrderId },
      dedupeKey: `payment-retry:${order.id}:${now.toISOString().slice(0, 10)}`,
      alsoEmail: true,
    });
    await this.audit.record({
      actorUserId: actor.userId,
      actorRole: String(actor.roleId),
      action: 'payment_remind',
      resource: 'payment_order',
      subjectUserId: order.userId,
      meta: { order_id: order.cashfreeOrderId, status: order.status },
      ip: actor.ip ?? null,
    });
  }

  private async find(cashfreeOrderId: string): Promise<PaymentOrderEntity> {
    const order = await this.orders.findOne({ where: { cashfreeOrderId } });
    if (!order) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'PAYMENT_NOT_FOUND', user_message: 'No such payment.' },
      });
    }
    return order;
  }

  private async people(ids: number[]): Promise<Map<number, UserEntity>> {
    if (ids.length === 0) return new Map();
    const rows = await this.users.find({
      where: { id: In([...new Set(ids)]) },
    });
    return new Map(rows.map((u) => [u.id, u]));
  }

  private row(o: PaymentOrderEntity, u: UserEntity | undefined): PaymentRow {
    return {
      order_id: o.cashfreeOrderId,
      user_id: o.userId,
      user_name: [u?.firstName, u?.lastName].filter(Boolean).join(' '),
      email: u?.email ?? null,
      email_masked: maskEmail(u?.email ?? null),
      amount_paise: String(o.amountPaise),
      discount_paise: String(o.discountPaise ?? '0'),
      coupon: o.couponCode,
      plan: `${o.tier} ${o.duration}`,
      kind: o.kind,
      status: o.status,
      gateway: 'cashfree',
      via_play_choice: !!o.externalTransactionToken,
      failure_reason: o.failureReason,
      created_at: o.createdAt.toISOString(),
      paid_at: o.paidAt?.toISOString() ?? null,
      refunded_at: o.refundedAt?.toISOString() ?? null,
    };
  }
}
