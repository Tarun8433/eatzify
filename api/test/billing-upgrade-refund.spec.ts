import { UnprocessableEntityException } from '@nestjs/common';
import { type Repository } from 'typeorm';
import { CheckoutService } from '../src/billing/checkout.service';
import { RefundService } from '../src/billing/refund.service';
import { PaymentOrderEntity } from '../src/billing/entities/payment-order.entity';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import { CommissionService } from '../src/partner/commission.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { CashfreeClient } from '../src/billing/cashfree.client';
import { PRICES } from '../src/billing/tiers';

/// docs/11 §7 and §9. Moving up mid-term, and giving the money back inside the week.

const NOW = new Date('2026-09-18T10:00:00Z');
const DAY = 86_400_000;

type Order = Partial<PaymentOrderEntity>;
type Sub = Partial<SubscriptionEntity>;

async function refusal(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (e as UnprocessableEntityException).getResponse() as {
      error: { code: string };
    };
    return body.error.code;
  }
  throw new Error('expected the request to be refused');
}

function upgradeSetup({
  credit = 100_000,
  price = PRICES.PRO['6M'],
}: { credit?: number; price?: number } = {}) {
  const orders: Order[] = [];
  const subs: Sub[] = [
    {
      id: 'old',
      userId: 1,
      tier: 'BASIC',
      status: 'active',
      startsAt: new Date(NOW.getTime() - 30 * DAY),
      currentPeriodEnd: new Date(NOW.getTime() + 60 * DAY),
      paidPaise: '119900',
      priceKey: 'BASIC:6M',
      autoRenew: true,
    },
  ];
  const gateway: { orderId: string; amountPaise: bigint }[] = [];

  const service = new CheckoutService(
    {
      create: (row: Order) => row,
      save: (row: Order) => {
        const at = orders.findIndex(
          (o) => o.cashfreeOrderId === row.cashfreeOrderId,
        );
        if (at >= 0) orders[at] = { ...orders[at], ...row };
        else orders.push({ ...row, id: `o${orders.length + 1}` });
        return Promise.resolve(row);
      },
      findOne: ({ where }: { where: Record<string, unknown> }) =>
        Promise.resolve(
          orders.find((o) =>
            Object.entries(where).every(
              ([k, v]) => (o as Record<string, unknown>)[k] === v,
            ),
          ) ?? null,
        ),
    } as never,
    {
      create: (row: Sub) => row,
      save: (row: Sub) => {
        const at = subs.findIndex((s) => s.id && s.id === row.id);
        if (at >= 0) subs[at] = { ...subs[at], ...row };
        else subs.push({ ...row, id: `s${subs.length + 1}` });
        return Promise.resolve(row);
      },
      findOne: () =>
        Promise.resolve(subs.find((s) => s.status === 'active') ?? null),
    } as never,
    {
      findOne: () => Promise.resolve({ id: 1, phone: '+919000000702' }),
    } as never,
    {
      mode: 'stub',
      createOrder: (r: { orderId: string; amountPaise: bigint }) => {
        gateway.push(r);
        return Promise.resolve({ paymentSessionId: 'session' });
      },
    } as never,
    { accrueFor: () => Promise.resolve(null) } as never,
    {
      upgradeQuote: () =>
        Promise.resolve({
          tier: 'PRO',
          duration: '6M',
          price_paise: price,
          proration: {
            remaining_days: 60,
            total_days: 90,
            unused_paise: credit,
            credit_paise: credit,
            amount_due_paise: price - credit,
          },
        }),
    } as never,
    // D-236: no coupon in these cases; discountFor never called, redeem is a no-op.
    {
      discountFor: () => Promise.resolve(null),
      redeem: () => Promise.resolve(),
    } as never,
  );

  return { service, orders, subs, gateway };
}

const UPGRADE = {
  userId: 1,
  tier: 'PRO' as const,
  duration: '6M' as const,
  idempotencyKey: null,
  now: NOW,
};

describe('a mid-term upgrade (docs/11 §7)', () => {
  it('should charge the difference, and keep the credit on the order', async () => {
    const { service, orders, gateway } = upgradeSetup({ credit: 100_000 });

    await service.upgrade(UPGRADE);

    expect(orders[0]).toMatchObject({
      kind: 'upgrade',
      amountPaise: String(PRICES.PRO['6M'] - 100_000),
      creditPaise: '100000',
    });
    expect(gateway[0]?.amountPaise).toBe(BigInt(PRICES.PRO['6M'] - 100_000));
  });

  it('should settle without a gateway when the credit covers the whole price', async () => {
    const { service, orders, gateway } = upgradeSetup({
      credit: PRICES.PRO['6M'],
    });

    await service.upgrade(UPGRADE);

    expect(gateway).toHaveLength(0);
    expect(orders[0]?.status).toBe('paid');
  });

  it('should close the period it replaces and open a new one (never mutate the old row)', async () => {
    const { service, subs } = upgradeSetup({ credit: PRICES.PRO['6M'] });

    await service.upgrade(UPGRADE);

    const old = subs.find((s) => s.id === 'old');
    expect(old).toMatchObject({ status: 'cancelled', tier: 'BASIC' });
    expect(old?.currentPeriodEnd?.getTime()).toBe(NOW.getTime());

    const fresh = subs.find((s) => s.id !== 'old');
    expect(fresh).toMatchObject({
      tier: 'PRO',
      status: 'active',
      autoRenew: true,
    });
    expect(fresh?.startsAt?.getTime()).toBe(NOW.getTime());
  });
});

function refundSetup({
  paidAt = new Date(NOW.getTime() - 2 * DAY),
}: { paidAt?: Date } = {}) {
  const order: Order = {
    id: 'o1',
    userId: 1,
    cashfreeOrderId: 'eatzify_1',
    tier: 'PRO',
    duration: '6M',
    amountPaise: '279900',
    status: 'paid',
    paidAt,
  };
  const sub: Sub = {
    id: 's1',
    userId: 1,
    tier: 'PRO',
    status: 'active',
    currentPeriodEnd: new Date(NOW.getTime() + 150 * DAY),
    autoRenew: true,
    providerRef: 'eatzify_1',
  };

  const refunded: { orderId: string; amountPaise: bigint }[] = [];
  const reversed: string[] = [];
  const sent: { kind: string }[] = [];

  const service = new RefundService(
    {
      findOne: ({ where }: { where: Record<string, unknown> }) =>
        Promise.resolve(
          where.cashfreeOrderId === order.cashfreeOrderId ? order : null,
        ),
      save: (row: Order) => Promise.resolve(row),
    } as unknown as Repository<PaymentOrderEntity>,
    {
      findOne: () => Promise.resolve(sub),
      save: (row: Sub) => Promise.resolve(row),
    } as unknown as Repository<SubscriptionEntity>,
    {
      refund: (r: { orderId: string; amountPaise: bigint }) => {
        refunded.push(r);
        return Promise.resolve();
      },
    } as unknown as CashfreeClient,
    {
      reverseForOrder: (id: string) => {
        reversed.push(id);
        return Promise.resolve();
      },
    } as unknown as CommissionService,
    {
      notify: (input: { kind: string }) => {
        sent.push(input);
        return Promise.resolve({ id: 'n1' });
      },
    } as unknown as NotificationsService,
  );

  return { service, order, sub, refunded, reversed, sent };
}

describe('a refund inside the week (docs/11 §9)', () => {
  it('should give the money back, end the plan and reverse the commission', async () => {
    const { service, order, sub, refunded, reversed, sent } = refundSetup();

    const view = await service.refund(1, 'eatzify_1', 'changed my mind', NOW);

    expect(refunded[0]).toMatchObject({
      orderId: 'eatzify_1',
      amountPaise: BigInt(279_900),
    });
    expect(order.status).toBe('refunded');
    expect(order.refundedAt).toBe(NOW);
    expect(sub).toMatchObject({ status: 'cancelled', autoRenew: false });
    expect(sub.currentPeriodEnd).toBe(NOW);
    expect(reversed).toEqual(['o1']);
    expect(sent[0]?.kind).toBe('refund_processed');
    expect(view).toMatchObject({ order_id: 'eatzify_1', tier_after: 'FREE' });
  });

  it('should refuse once the seven days are up', async () => {
    const { service, refunded } = refundSetup({
      paidAt: new Date(NOW.getTime() - 8 * DAY),
    });

    expect(await refusal(service.refund(1, 'eatzify_1', null, NOW))).toBe(
      'REFUND_WINDOW_CLOSED',
    );
    expect(refunded).toHaveLength(0);
  });

  it('should refuse an order that was never paid', async () => {
    const { service, order } = refundSetup();
    order.status = 'created';

    expect(await refusal(service.refund(1, 'eatzify_1', null, NOW))).toBe(
      'REFUND_NOT_AVAILABLE',
    );
  });

  it('should refuse an order that belongs to nobody it knows', async () => {
    const { service } = refundSetup();

    expect(await refusal(service.refund(1, 'eatzify_other', null, NOW))).toBe(
      'REFUND_NOT_AVAILABLE',
    );
  });
});
