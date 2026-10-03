import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, LessThan, MoreThan, Repository } from 'typeorm';
import { PaymentOrderEntity } from '../billing/entities/payment-order.entity';
import { RefundRequestEntity } from '../billing/entities/refund-request.entity';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import { StatusEnum } from '../statuses/statuses.enum';
import { TicketEntity } from '../tickets/entities/ticket.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { can, type Permission } from './permissions';

export type AdminAlert = {
  kind: string;
  count: number;
  /// The dashboard screen that deals with it.
  nav: string;
};

/// More failed payments than this in an hour is worth a look (a gateway or bank problem).
export const FAILED_PAYMENTS_ALERT = 5;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/// The bell (admin panel plan, Phase C): what is waiting on the team right now, counted from the
/// queues themselves rather than stored, so it can never drift from what the screens show. Each
/// role sees only the queues it can act on.
@Injectable()
export class AdminAlertsService {
  constructor(
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    @InjectRepository(RefundRequestEntity)
    private readonly refunds: Repository<RefundRequestEntity>,
    @InjectRepository(TicketEntity)
    private readonly tickets: Repository<TicketEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity>,
  ) {}

  async for(
    roleId: number | string | undefined,
    now = new Date(),
  ): Promise<AdminAlert[]> {
    const checks: [Permission, string, string, () => Promise<number>][] = [
      [
        'verification.manage',
        'coach_applications',
        'partners',
        () => this.applications.count({ where: { status: 'submitted' } }),
      ],
      [
        'refunds.manage',
        'refund_requests',
        'refunds',
        () => this.refunds.count({ where: { status: 'requested' } }),
      ],
      [
        'users.read',
        'tickets_waiting',
        'tickets',
        () => this.tickets.count({ where: { status: In(['new', 'open']) } }),
      ],
      [
        'users.manage',
        'emails_unconfirmed_24h',
        'verification',
        () =>
          this.users.count({
            where: {
              status: { id: StatusEnum.inactive },
              createdAt: LessThan(new Date(now.getTime() - DAY_MS)),
              isDemo: false,
            },
          }),
      ],
      [
        'payments.read',
        'failed_payments_last_hour',
        'payments',
        async () => {
          const n = await this.orders.count({
            where: {
              status: 'failed',
              createdAt: MoreThan(new Date(now.getTime() - HOUR_MS)),
            },
          });
          return n >= FAILED_PAYMENTS_ALERT ? n : 0;
        },
      ],
    ];
    const mine = checks.filter(([permission]) => can(roleId, permission));
    const counts = await Promise.all(mine.map(([, , , count]) => count()));
    return mine
      .map(([, kind, nav], i) => ({ kind, nav, count: counts[i] }))
      .filter((a) => a.count > 0);
  }
}
