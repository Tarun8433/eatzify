import { UnprocessableEntityException } from '@nestjs/common';
import { CheckoutService } from '../src/billing/checkout.service';
import type { PaymentOrderEntity } from '../src/billing/entities/payment-order.entity';
import type { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import { PRICES } from '../src/billing/tiers';

/// docs/11 §5. The property this whole file exists to defend: **a subscription is granted by a
/// verified payment and by nothing else.** Not by an order existing, not by the app saying so.

const NOW = new Date('2026-09-15T00:00:00Z');

function serviceWith({
  subscription = null as Partial<SubscriptionEntity> | null,
  phone = '+919000000001' as string | null,
  gatewayFails = false,
} = {}) {
  // Partial, because the real entity extends TypeORM's `BaseEntity` and a fake row has none of
  // its instance methods — which the service never touches.
  const orders: Partial<PaymentOrderEntity>[] = [];
  let sub = subscription as SubscriptionEntity | null;
  const gatewayCalls: { orderId: string; amountPaise: bigint }[] = [];
  const accruals: { isRenewal: boolean }[] = [];

  const service = new CheckoutService(
    {
      create: (row: Partial<PaymentOrderEntity>) => row as PaymentOrderEntity,
      save: (row: PaymentOrderEntity) => {
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
              ([k, v]) => o[k as keyof PaymentOrderEntity] === v,
            ),
          ) ?? null,
        ),
    } as never,
    {
      findOne: () => Promise.resolve(sub),
      save: (row: SubscriptionEntity) => {
        sub = { ...sub, ...row } as SubscriptionEntity;
        return Promise.resolve(sub);
      },
    } as never,
    {
      findOne: () => Promise.resolve(phone ? { id: 1, phone } : null),
    } as never,
    {
      mode: 'stub',
      createOrder: (args: { orderId: string; amountPaise: bigint }) => {
        gatewayCalls.push(args);
        if (gatewayFails) return Promise.reject(new Error('CASHFREE_DOWN'));
        return Promise.resolve({ paymentSessionId: 'session_1' });
      },
    } as never,
    {
      accrueFor: (args: { isRenewal: boolean }) => {
        accruals.push(args);
        return Promise.resolve(null);
      },
    } as never,
    // Only the upgrade path asks it anything, and these cases are plain purchases.
    {
      upgradeQuote: () =>
        Promise.reject(new Error('not an upgrade in these tests')),
    } as never,
    // D-236: no coupon in these cases; discountFor never called, redeem is a no-op.
    {
      discountFor: () => Promise.resolve(null),
      redeem: () => Promise.resolve(),
    } as never,
  );

  return { service, orders, gatewayCalls, accruals, subscription: () => sub };
}

/// `noUncheckedIndexedAccess` makes every fake row optional. Asserting once here beats a `!` on
/// every line, and it fails with a sentence rather than a null dereference.
function idOf(order: Partial<PaymentOrderEntity> | undefined): string {
  if (!order?.cashfreeOrderId) throw new Error('no order was created');
  return order.cashfreeOrderId;
}

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

const BUY = {
  userId: 1,
  tier: 'PRO' as const,
  duration: '3M' as const,
  idempotencyKey: null,
  now: NOW,
};

describe('starting a purchase', () => {
  /// The body names a CELL in the matrix, never an amount. A request that could carry its own
  /// price would carry ₹1.
  it('should take the price from the matrix, not from the caller', async () => {
    const { service, gatewayCalls } = serviceWith();

    await service.checkout(BUY);

    expect(gatewayCalls[0]?.amountPaise).toBe(BigInt(PRICES.PRO['3M']));
  });

  it('should grant nothing until the payment is confirmed', async () => {
    const { service, subscription } = serviceWith();

    await service.checkout(BUY);

    expect(subscription()).toBeNull();
  });

  /// docs/09: a retried POST must not open a second order, and must not charge twice.
  it('should return the first order when the same key is sent again', async () => {
    const { service, gatewayCalls } = serviceWith();

    const first = await service.checkout({ ...BUY, idempotencyKey: 'k1' });
    const again = await service.checkout({ ...BUY, idempotencyKey: 'k1' });

    expect(again.order_id).toBe(first.order_id);
    expect(gatewayCalls).toHaveLength(1);
  });

  /// Cashfree needs a contactable customer and an email signup has no number on the row. Refusing
  /// beats sending the gateway an order it will reject.
  it('should refuse when the account has no phone number', async () => {
    const { service } = serviceWith({ phone: null });

    expect(await refusal(service.checkout(BUY))).toBe('PHONE_REQUIRED');
  });

  /// docs/11 §7 makes a mid-term change a proration calculation with a credit, and that is not
  /// built. Charging a second full price for it would be the wrong answer, not a simpler one.
  it('should refuse a second plan while one is still running', async () => {
    const { service } = serviceWith({
      subscription: {
        tier: 'BASIC',
        status: 'active',
        currentPeriodEnd: new Date('2026-12-01T00:00:00Z'),
      },
    });

    expect(await refusal(service.checkout(BUY))).toBe('ALREADY_SUBSCRIBED');
  });

  /// An order the gateway knows about and we do not is a payment nobody can honour. The row is
  /// written first and marked failed after, so support can always see the attempt.
  it('should keep the failed attempt on record when the gateway refuses', async () => {
    const { service, orders } = serviceWith({ gatewayFails: true });

    expect(await refusal(service.checkout(BUY))).toBe('CHECKOUT_UNAVAILABLE');
    expect(orders[0]?.status).toBe('failed');
  });
});

describe('a confirmed payment', () => {
  it('should activate the tier that was bought', async () => {
    const { service, orders, subscription } = serviceWith();
    await service.checkout(BUY);

    await service.markPaid(idOf(orders[0]), NOW);

    expect(subscription()?.tier).toBe('PRO');
    expect(subscription()?.status).toBe('active');
    // 3M from today.
    expect(subscription()?.currentPeriodEnd?.toISOString()).toBe(
      '2026-12-15T00:00:00.000Z',
    );
  });

  /// A gateway retries a slow response. The second delivery of the same success must not extend
  /// the plan a second time.
  it('should not extend the plan twice when the webhook arrives twice', async () => {
    const { service, orders, subscription } = serviceWith();
    await service.checkout(BUY);
    const id = idOf(orders[0]);

    await service.markPaid(id, NOW);
    const after = subscription()?.currentPeriodEnd?.toISOString();
    await service.markPaid(id, NOW);

    expect(subscription()?.currentPeriodEnd?.toISOString()).toBe(after);
  });

  /// Renewing early must keep the days already paid for. Anyone who renews a month ahead would
  /// otherwise lose that month.
  it('should extend from the end of a running period, not from today', async () => {
    const { service, orders, subscription } = serviceWith({
      subscription: {
        tier: 'PRO',
        status: 'active',
        currentPeriodEnd: new Date('2026-10-15T00:00:00Z'),
      },
    });
    // The guard is on checkout, so a renewal reaches activation through the webhook.
    await service.markPaid('x', NOW);
    orders.push({
      cashfreeOrderId: 'renew',
      userId: 1,
      tier: 'PRO',
      duration: '3M',
      status: 'created',
    });

    await service.markPaid('renew', NOW);

    expect(subscription()?.currentPeriodEnd?.toISOString()).toBe(
      '2027-01-15T00:00:00.000Z',
    );
  });

  /// A failure arriving after a success is a retry of an earlier attempt, not a reversal.
  /// Reversals are refunds and have their own path (docs/11 §9).
  it('should never turn a paid order back into a failed one', async () => {
    const { service, orders } = serviceWith();
    await service.checkout(BUY);
    const id = idOf(orders[0]);
    await service.markPaid(id, NOW);

    await service.markFailed(id, 'declined', NOW);

    expect(orders[0]?.status).toBe('paid');
  });

  /// A webhook endpoint that answered differently for an unknown id would tell a prober which ids
  /// are real.
  it('should do nothing, quietly, for an order id it has never seen', async () => {
    const { service, subscription } = serviceWith();

    await service.markPaid('eatzify_not_a_real_order', NOW);

    expect(subscription()).toBeNull();
  });
});

describe('the stub simulate route', () => {
  /// It stands in for the gateway, so it must drive the SAME activation the webhook does —
  /// otherwise the path being tested is not the path that ships.
  it('should activate exactly as a webhook would', async () => {
    const { service, orders, subscription } = serviceWith();
    await service.checkout(BUY);

    await service.simulatePaid(1, idOf(orders[0]), NOW);

    expect(subscription()?.tier).toBe('PRO');
  });

  /// Scoped to the caller's own orders. Otherwise a stub build hands anyone who can guess an order
  /// id somebody else's subscription.
  it('should ignore an order belonging to somebody else', async () => {
    const { service, orders, subscription } = serviceWith();
    await service.checkout(BUY);

    await service.simulatePaid(999, idOf(orders[0]), NOW);

    expect(subscription()).toBeNull();
  });
});

describe('crediting the partner who referred the buyer', () => {
  /// docs/12 §3. The commission is written from the confirmed payment and nowhere else — the same
  /// place, and the same guarantee, that activates the subscription.
  it('should accrue against the order once the payment is confirmed', async () => {
    const { service, orders, accruals } = serviceWith();
    await service.checkout(BUY);

    await service.markPaid(idOf(orders[0]), NOW);

    expect(accruals).toHaveLength(1);
  });

  it('should accrue nothing for an order that was never paid', async () => {
    const { service, accruals } = serviceWith();

    await service.checkout(BUY);

    expect(accruals).toEqual([]);
  });

  /// docs/12 §2 pays a lower rate on a renewal, so the two have to be told apart at the moment the
  /// entry is written. Anyone who has held a paid tier before is renewing.
  it('should call a first sale a first purchase', async () => {
    const { service, orders, accruals } = serviceWith();
    await service.checkout(BUY);

    await service.markPaid(idOf(orders[0]), NOW);

    expect(accruals[0]?.isRenewal).toBe(false);
  });

  it('should call a repeat sale a renewal', async () => {
    const { service, orders, accruals } = serviceWith({
      subscription: {
        tier: 'PRO',
        status: 'expired',
        currentPeriodEnd: new Date('2026-08-01T00:00:00Z'),
      },
    });
    await service.checkout(BUY);

    await service.markPaid(idOf(orders[0]), NOW);

    expect(accruals[0]?.isRenewal).toBe(true);
  });
});
