import {
  ConflictException,
  HttpStatus,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { NotificationsService } from '../notifications/notifications.service';
import {
  REFUND_NOT_AVAILABLE,
  REFUND_REQUEST_DECIDED,
  REFUND_REQUEST_NOT_FOUND,
  REFUND_REQUEST_OPEN,
  REFUND_USE_SELF_SERVE,
} from './billing-copy';
import { PaymentOrderEntity } from './entities/payment-order.entity';
import {
  RefundRequestEntity,
  type RefundRequestStatus,
} from './entities/refund-request.entity';
import { REFUND_DAYS, RefundService, type RefundView } from './refund.service';

const MS_PER_DAY = 86_400_000;

export type RefundRequestView = {
  id: string;
  order_id: string;
  user_id: number;
  amount_paise: string;
  plan: string;
  paid_at: string | null;
  reason: string;
  status: RefundRequestStatus;
  decided_by: number | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
};

/// One of the person's own payments, and what they can do about it (`GET /billing/payments`).
export type PaidOrderView = {
  order_id: string;
  amount_paise: string;
  plan: string;
  paid_at: string | null;
  status: 'paid' | 'refunded';
  /// `self_serve`: refund now (inside 7 days). `request`: ask, and finance decides. `requested`:
  /// already asked. Null: nothing to refund.
  refund: 'self_serve' | 'request' | 'requested' | null;
};

/// Admin panel plan, Phase B: refunds asked for after the 7-day self-serve window (docs/11 §9).
/// The person asks from the app; finance approves (the refund runs exactly as self-serve does) or
/// rejects with a note the person is sent.
@Injectable()
export class RefundRequestService {
  constructor(
    @InjectRepository(RefundRequestEntity)
    private readonly requests: Repository<RefundRequestEntity>,
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
    private readonly refunds: RefundService,
    private readonly notifications: NotificationsService,
  ) {}

  /// `POST /billing/refund-request`, from the app.
  async request(
    userId: number,
    cashfreeOrderId: string,
    reason: string,
    now: Date,
  ): Promise<RefundRequestView> {
    const order = await this.orders.findOne({
      where: { cashfreeOrderId, userId },
    });
    if (!order || order.status !== 'paid' || !order.paidAt) {
      throw this.unprocessable('REFUND_NOT_AVAILABLE', REFUND_NOT_AVAILABLE);
    }
    if ((now.getTime() - order.paidAt.getTime()) / MS_PER_DAY <= REFUND_DAYS) {
      throw this.unprocessable('REFUND_USE_SELF_SERVE', REFUND_USE_SELF_SERVE);
    }
    const open = await this.requests.findOne({
      where: { orderId: order.id, status: 'requested' },
    });
    if (open) {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: {
          code: 'REFUND_REQUEST_OPEN',
          user_message: REFUND_REQUEST_OPEN,
        },
      });
    }
    const saved = await this.requests.save(
      this.requests.create({
        orderId: order.id,
        userId,
        reason: reason.trim(),
      }),
    );
    return this.view(saved, order);
  }

  /// The person's paid and refunded orders, newest first, with the refund each allows.
  async paidOrdersFor(userId: number, now: Date): Promise<PaidOrderView[]> {
    const orders = await this.orders.find({
      where: { userId, status: In(['paid', 'refunded']) },
      order: { paidAt: 'DESC' },
      take: 50,
    });
    const open = await this.requests.find({
      where: { userId, status: 'requested' },
    });
    const asked = new Set(open.map((r) => r.orderId));
    return orders.map((o) => {
      const inWindow =
        !!o.paidAt &&
        (now.getTime() - o.paidAt.getTime()) / MS_PER_DAY <= REFUND_DAYS;
      const refund: PaidOrderView['refund'] =
        o.status !== 'paid'
          ? null
          : asked.has(o.id)
            ? 'requested'
            : inWindow
              ? 'self_serve'
              : 'request';
      return {
        order_id: o.cashfreeOrderId,
        amount_paise: String(o.amountPaise),
        plan: `${o.tier} ${o.duration}`,
        paid_at: o.paidAt?.toISOString() ?? null,
        status: o.status as 'paid' | 'refunded',
        refund,
      };
    });
  }

  async list(
    status: RefundRequestStatus | undefined,
    limit = 100,
  ): Promise<RefundRequestView[]> {
    const rows = await this.requests.find({
      where: status ? { status } : {},
      order: { createdAt: status === 'requested' ? 'ASC' : 'DESC' },
      take: Math.min(limit, 200),
    });
    const orders = await this.orders.find({
      where: { id: In(rows.map((r) => r.orderId)) },
    });
    const byId = new Map(orders.map((o) => [o.id, o]));
    return rows.map((r) => this.view(r, byId.get(r.orderId)));
  }

  async approve(
    id: string,
    adminId: number,
    now: Date,
  ): Promise<{ request: RefundRequestView; refund: RefundView }> {
    const { request, order } = await this.open(id);
    const refund = await this.refunds.refundAsAdmin(
      order.cashfreeOrderId,
      request.reason,
      now,
    );
    request.status = 'approved';
    request.decidedBy = adminId;
    request.decidedAt = now;
    await this.requests.save(request);
    return { request: this.view(request, order), refund };
  }

  async reject(
    id: string,
    note: string,
    adminId: number,
    now: Date,
  ): Promise<RefundRequestView> {
    const { request, order } = await this.open(id);
    request.status = 'rejected';
    request.decidedBy = adminId;
    request.decidedAt = now;
    request.decisionNote = note.trim();
    await this.requests.save(request);
    await this.notifications.notify({
      userId: request.userId,
      kind: 'refund_rejected',
      contentClass: 'service',
      title: 'About your refund request',
      body: request.decisionNote,
      data: { order_id: order.cashfreeOrderId },
      dedupeKey: `refund-request:${request.id}`,
      alsoEmail: true,
    });
    return this.view(request, order);
  }

  private async open(
    id: string,
  ): Promise<{ request: RefundRequestEntity; order: PaymentOrderEntity }> {
    const request = await this.requests.findOne({ where: { id } });
    if (!request) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: {
          code: 'REFUND_REQUEST_NOT_FOUND',
          user_message: REFUND_REQUEST_NOT_FOUND,
        },
      });
    }
    if (request.status !== 'requested') {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: {
          code: 'REFUND_REQUEST_DECIDED',
          user_message: REFUND_REQUEST_DECIDED,
        },
      });
    }
    const order = await this.orders.findOneOrFail({
      where: { id: request.orderId },
    });
    return { request, order };
  }

  private view(
    r: RefundRequestEntity,
    o: PaymentOrderEntity | undefined,
  ): RefundRequestView {
    return {
      id: r.id,
      order_id: o?.cashfreeOrderId ?? '',
      user_id: r.userId,
      amount_paise: String(o?.amountPaise ?? '0'),
      plan: o ? `${o.tier} ${o.duration}` : '',
      paid_at: o?.paidAt?.toISOString() ?? null,
      reason: r.reason,
      status: r.status,
      decided_by: r.decidedBy,
      decided_at: r.decidedAt?.toISOString() ?? null,
      decision_note: r.decisionNote,
      created_at: r.createdAt.toISOString(),
    };
  }

  private unprocessable(code: string, message: string) {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: message },
    });
  }
}
