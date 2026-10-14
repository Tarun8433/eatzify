import { ForbiddenException, HttpException } from '@nestjs/common';
import { BillingController } from '../src/billing/billing.controller';
import { CheckoutService } from '../src/billing/checkout.service';
import type { PaymentOrderEntity } from '../src/billing/entities/payment-order.entity';
import type { PersonalOfferEntity } from '../src/billing/entities/personal-offer.entity';
import { PersonalOffersService } from '../src/billing/offers/personal-offers.service';
import { OFFER_ERRORS } from '../src/billing/offers/personal-offer-rules';
import { PriceService } from '../src/billing/price.service';
import { OFFER_NOT_FOUND } from '../src/billing/billing-copy';
import { PRICES } from '../src/billing/tiers';

/// D-265: personal offers end to end, against fakes. The properties defended: a code answers only
/// its owner and only while live (one 404 for everything else), checkout charges the STORED amount,
/// and the offer is spent only by a confirmed payment.

const NOW = new Date('2026-10-14T10:00:00Z');
const LATER = new Date('2026-10-21T10:00:00Z');
const EARLIER = new Date('2026-10-01T10:00:00Z');
const CODE = 'Zx9_-Zx9_-Zx9_-Zx9_-Zx';

function row(over: Partial<PersonalOfferEntity> = {}): PersonalOfferEntity {
  return {
    id: '00000000-0000-4000-8000-000000000001',
    code: CODE,
    userId: 7,
    tier: 'PRO',
    duration: '3M',
    channel: 'cashfree',
    playProductId: null,
    playBasePlanId: null,
    playOfferId: null,
    amountPaise: '99900',
    note: null,
    expiresAt: LATER,
    usedAt: null,
    revokedAt: null,
    createdByUserId: 1,
    createdAt: EARLIER,
    ...over,
  } as PersonalOfferEntity;
}

const PLAY_ROW = {
  channel: 'play' as const,
  amountPaise: null,
  playProductId: 'eatzify_premium',
  playBasePlanId: 'p3m',
  playOfferId: 'special',
};

function harness({
  rows = [] as PersonalOfferEntity[],
  playConfigured = true,
  userExists = true,
  cashfree = undefined as { mode: string; androidEnabled: boolean } | undefined,
} = {}) {
  const store = [...rows];
  const checkouts: Record<string, unknown>[] = [];
  const offers = {
    create: (r: Partial<PersonalOfferEntity>) => r as PersonalOfferEntity,
    save: (r: PersonalOfferEntity) => {
      const saved = { ...r, id: r.id ?? `id-${store.length + 1}` };
      const at = store.findIndex((s) => s.id === saved.id);
      if (at >= 0) store[at] = saved as PersonalOfferEntity;
      else store.push(saved as PersonalOfferEntity);
      return Promise.resolve(saved);
    },
    findOne: ({ where }: { where: Partial<PersonalOfferEntity> }) =>
      Promise.resolve(
        store.find((s) =>
          Object.entries(where).every(
            ([k, v]) => s[k as keyof PersonalOfferEntity] === v,
          ),
        ) ?? null,
      ),
    find: ({ where }: { where: { userId: number } }) =>
      Promise.resolve(
        store
          .filter((s) => s.userId === where.userId)
          .sort((a, b) => +b.createdAt - +a.createdAt),
      ),
    update: (where: { id: string }, patch: Partial<PersonalOfferEntity>) => {
      const at = store.findIndex((s) => s.id === where.id);
      if (at >= 0)
        store[at] = { ...store[at], ...patch } as PersonalOfferEntity;
      return Promise.resolve();
    },
  };
  const service = new PersonalOffersService(
    offers as never,
    { count: () => Promise.resolve(userExists ? 1 : 0) } as never,
    new PriceService({ find: () => Promise.resolve([]) } as never),
    {
      configured: playConfigured,
      subscriptionCatalog: () =>
        Promise.resolve({
          subscriptions: [
            {
              productId: 'eatzify_premium',
              basePlans: [{ basePlanId: 'p3m', state: 'ACTIVE' }],
            },
          ],
          offers: [
            {
              productId: 'eatzify_premium',
              basePlanId: 'p3m',
              offerId: 'special',
              state: 'ACTIVE',
              phases: [
                {
                  regionalConfigs: [
                    {
                      regionCode: 'IN',
                      price: { currencyCode: 'INR', units: '1299' },
                    },
                  ],
                },
              ],
            },
          ],
        }),
    } as never,
    {
      checkout: (args: Record<string, unknown>) => {
        checkouts.push(args);
        return Promise.resolve({ order_id: 'o1' });
      },
    } as never,
    { getOrThrow: () => 'https://api.example.test' } as never,
    cashfree as never,
  );
  return { service, store, checkouts };
}

async function errorOf(run: Promise<unknown>) {
  try {
    await run;
  } catch (e) {
    const ex = e as HttpException;
    return {
      status: ex.getStatus(),
      body: ex.getResponse() as {
        error: { code: string; user_message: string };
      },
    };
  }
  throw new Error('expected a refusal');
}

describe('creating a personal offer', () => {
  const cashfreeOffer = {
    userId: 7,
    channel: 'cashfree' as const,
    tier: 'BASIC' as const,
    duration: '1M' as const,
    amountPaise: 100,
  };

  /// The offer the phone screenshot showed: ₹1, with no way to pay it on Android.
  it('should refuse a cashfree offer when no app can pay it yet', async () => {
    const { service, store } = harness({
      cashfree: { mode: 'production', androidEnabled: false },
    });

    const refused = await errorOf(service.create(cashfreeOffer, 1, NOW));

    expect(refused.status).toBe(422);
    expect(refused.body.error.user_message).toMatch(/Google Play offer/);
    expect(store).toHaveLength(0);
  });

  it('should allow a cashfree offer when User Choice Billing is on', async () => {
    const { service, store } = harness({
      cashfree: { mode: 'production', androidEnabled: true },
    });
    await service.create(cashfreeOffer, 1, NOW);
    expect(store).toHaveLength(1);
  });

  it('should allow a cashfree offer when in stub mode, which moves no money', async () => {
    const { service, store } = harness({
      cashfree: { mode: 'stub', androidEnabled: false },
    });
    await service.create(cashfreeOffer, 1, NOW);
    expect(store).toHaveLength(1);
  });

  it('should store a cashfree offer and answer with its code and link when valid', async () => {
    const { service, store } = harness();
    const view = await service.create(
      {
        userId: 7,
        channel: 'cashfree',
        tier: 'PRO',
        duration: '3M',
        amountPaise: 99_900,
        note: ' retention ',
      },
      1,
      NOW,
    );
    expect(view.code).toHaveLength(22);
    expect(view.link).toBe(`https://api.example.test/offer/${view.code}`);
    expect(view.status).toBe('active');
    expect(view.expires_at).toBe(LATER.toISOString());
    expect(store[0]).toMatchObject({ amountPaise: '99900', note: 'retention' });
  });

  it('should refuse a cashfree amount above the normal price when created', async () => {
    const { service, store } = harness();
    const refused = await errorOf(
      service.create(
        {
          userId: 7,
          channel: 'cashfree',
          tier: 'PRO',
          duration: '3M',
          amountPaise: PRICES.PRO['3M'] + 1,
        },
        1,
        NOW,
      ),
    );
    expect(refused.body.error.user_message).toBe(OFFER_ERRORS.amountTooHigh);
    expect(store).toHaveLength(0);
  });

  it('should store a play offer when it matches an active catalogue entry', async () => {
    const { service, store } = harness();
    await service.create(
      {
        userId: 7,
        channel: 'play',
        tier: 'PRO',
        duration: '3M',
        playProductId: 'eatzify_premium',
        playBasePlanId: 'p3m',
        playOfferId: 'special',
      },
      1,
      NOW,
    );
    expect(store[0]).toMatchObject({
      playOfferId: 'special',
      amountPaise: null,
    });
  });

  it('should refuse a play offer when it is not in the catalogue', async () => {
    const { service } = harness();
    const refused = await errorOf(
      service.create(
        {
          userId: 7,
          channel: 'play',
          tier: 'PRO',
          duration: '3M',
          playProductId: 'eatzify_premium',
          playBasePlanId: 'p3m',
          playOfferId: 'made-up',
        },
        1,
        NOW,
      ),
    );
    expect(refused.body.error.user_message).toBe(OFFER_ERRORS.notInCatalogue);
  });

  it('should answer an empty catalogue when play is not configured', async () => {
    const { service } = harness({ playConfigured: false });
    await expect(service.playCatalog()).resolves.toEqual([]);
  });

  it('should refuse when the user does not exist', async () => {
    const { service } = harness({ userExists: false });
    const refused = await errorOf(
      service.create(
        {
          userId: 99,
          channel: 'cashfree',
          tier: 'PRO',
          duration: '3M',
          amountPaise: 100,
        },
        1,
        NOW,
      ),
    );
    expect(refused.status).toBe(404);
  });
});

describe('listing and revoking', () => {
  it('should list the user offers newest first with their status', async () => {
    const { service } = harness({
      rows: [
        row({ id: 'a', createdAt: EARLIER, usedAt: EARLIER }),
        row({ id: 'b', createdAt: NOW, code: 'other-code-0000000000' }),
      ],
    });
    const list = await service.listFor(7, NOW);
    expect(list.map((o) => [o.id, o.status])).toEqual([
      ['b', 'active'],
      ['a', 'used'],
    ]);
  });

  it('should keep the first revoke time when revoked twice', async () => {
    const { service } = harness({ rows: [row()] });
    const first = await service.revoke(row().id, NOW);
    const again = await service.revoke(row().id, LATER);
    expect(first.status).toBe('revoked');
    expect(again.revoked_at).toBe(NOW.toISOString());
  });
});

describe('the app reading an offer', () => {
  it('should answer the owner with the stored price and the regular one', async () => {
    const { service } = harness({ rows: [row()] });
    await expect(service.forCaller(7, CODE, NOW)).resolves.toEqual({
      code: CODE,
      channel: 'cashfree',
      tier: 'PRO',
      duration: '3M',
      expires_at: LATER.toISOString(),
      price_paise: 99_900,
      regular_price_paise: PRICES.PRO['3M'],
      play: null,
    });
  });

  it('should answer a play offer with its ids and the catalogue price', async () => {
    const { service } = harness({ rows: [row(PLAY_ROW)] });
    const view = await service.forCaller(7, CODE, NOW);
    expect(view.price_paise).toBe(129_900);
    expect(view.play).toEqual({
      product_id: 'eatzify_premium',
      base_plan_id: 'p3m',
      offer_id: 'special',
    });
  });

  it.each([
    ['unknown', [] as PersonalOfferEntity[], 7],
    ['another user', [row()], 8],
    ['expired', [row({ expiresAt: EARLIER })], 7],
    ['used', [row({ usedAt: EARLIER })], 7],
    ['revoked', [row({ revokedAt: EARLIER })], 7],
  ])(
    'should answer the same 404 when the offer is %s',
    async (_why, rows, userId) => {
      const { service } = harness({ rows });
      const refused = await errorOf(service.forCaller(userId, CODE, NOW));
      expect(refused).toEqual({
        status: 404,
        body: {
          status: 404,
          error: { code: 'OFFER_NOT_FOUND', user_message: OFFER_NOT_FOUND },
        },
      });
    },
  );
});

describe('paying for a cashfree offer', () => {
  it('should check out with the stored amount and the offer id', async () => {
    const { service, checkouts } = harness({ rows: [row()] });
    await service.startCheckout(7, CODE, 'key-1', NOW);
    expect(checkouts[0]).toMatchObject({
      userId: 7,
      tier: 'PRO',
      duration: '3M',
      idempotencyKey: 'key-1',
      personalOffer: { id: row().id, amountPaise: 99_900n },
    });
  });

  it('should refuse a play offer with 409 when checked out', async () => {
    const { service, checkouts } = harness({ rows: [row(PLAY_ROW)] });
    const refused = await errorOf(service.startCheckout(7, CODE, null, NOW));
    expect(refused.status).toBe(409);
    expect(refused.body.error.code).toBe('OFFER_NOT_CASHFREE');
    expect(checkouts).toHaveLength(0);
  });

  it('should refuse with 404 when the code is someone else', async () => {
    const { service, checkouts } = harness({ rows: [row()] });
    const refused = await errorOf(service.startCheckout(8, CODE, null, NOW));
    expect(refused.status).toBe(404);
    expect(checkouts).toHaveLength(0);
  });
});

describe('marking a play offer used', () => {
  const line = {
    productId: 'eatzify_premium',
    basePlanId: 'p3m',
    offerId: 'special',
  };

  it('should mark it used when the purchased offer matches', async () => {
    const { service, store } = harness({ rows: [row(PLAY_ROW)] });
    await expect(service.markUsedByPlay(7, CODE, line, NOW)).resolves.toBe(
      true,
    );
    expect(store[0]?.usedAt).toEqual(NOW);
  });

  it('should leave it unused when the purchased offer differs', async () => {
    const { service, store } = harness({ rows: [row(PLAY_ROW)] });
    await service.markUsedByPlay(7, CODE, { ...line, offerId: 'other' }, NOW);
    expect(store[0]?.usedAt).toBeNull();
  });

  it('should leave it unused when another user sends the code', async () => {
    const { service, store } = harness({ rows: [row(PLAY_ROW)] });
    await service.markUsedByPlay(8, CODE, line, NOW);
    expect(store[0]?.usedAt).toBeNull();
  });
});

/// The checkout service itself: the amount on the order and at the gateway is the offer's, and the
/// offer is spent by the verified payment, not by starting a checkout.
function checkoutWith() {
  const orders: Partial<PaymentOrderEntity>[] = [];
  const gateway: { amountPaise: bigint }[] = [];
  const spent: { where: unknown; patch: unknown }[] = [];
  const service = new CheckoutService(
    {
      create: (r: Partial<PaymentOrderEntity>) => r as PaymentOrderEntity,
      save: (r: PaymentOrderEntity) => {
        const at = orders.findIndex(
          (o) => o.cashfreeOrderId === r.cashfreeOrderId,
        );
        if (at >= 0) orders[at] = { ...orders[at], ...r };
        else orders.push({ ...r, id: `o${orders.length + 1}` });
        return Promise.resolve(r);
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
      findOne: () => Promise.resolve(null),
      save: (r: unknown) => Promise.resolve(r),
    } as never,
    {
      findOne: () => Promise.resolve({ id: 7, phone: '+919000000001' }),
    } as never,
    {
      mode: 'stub',
      createOrder: (args: { amountPaise: bigint }) => {
        gateway.push(args);
        return Promise.resolve({ paymentSessionId: 's1' });
      },
    } as never,
    { accrueFor: () => Promise.resolve(null) } as never,
    {} as never,
    {
      discountFor: () => Promise.resolve(null),
      redeem: () => Promise.resolve(),
    } as never,
    new PriceService({ find: () => Promise.resolve([]) } as never),
    null,
    null,
    {
      update: (where: unknown, patch: unknown) => {
        spent.push({ where, patch });
        return Promise.resolve();
      },
    } as never,
  );
  return { service, orders, gateway, spent };
}

describe('the offer order', () => {
  const OFFER = { id: row().id, amountPaise: 99_900n };

  it('should charge the stored amount and set personalOfferId when started', async () => {
    const { service, orders, gateway, spent } = checkoutWith();
    await service.checkout({
      userId: 7,
      tier: 'PRO',
      duration: '3M',
      idempotencyKey: null,
      now: NOW,
      couponCode: 'IGNORED',
      personalOffer: OFFER,
    });
    expect(gateway[0]?.amountPaise).toBe(99_900n);
    expect(orders[0]).toMatchObject({
      amountPaise: '99900',
      personalOfferId: OFFER.id,
      couponCode: null,
    });
    expect(spent).toHaveLength(0);
  });

  it('should mark the offer used when the payment is confirmed', async () => {
    const { service, orders, spent } = checkoutWith();
    await service.checkout({
      userId: 7,
      tier: 'PRO',
      duration: '3M',
      idempotencyKey: null,
      now: NOW,
      personalOffer: OFFER,
    });
    await service.markPaid(orders[0]!.cashfreeOrderId!, NOW);
    expect(spent).toHaveLength(1);
    expect(spent[0]?.patch).toEqual({ usedAt: NOW });
    expect(spent[0]?.where).toMatchObject({ id: OFFER.id });
  });

  it('should spend no offer when a plain order is paid', async () => {
    const { service, orders, spent } = checkoutWith();
    await service.checkout({
      userId: 7,
      tier: 'PRO',
      duration: '3M',
      idempotencyKey: null,
      now: NOW,
    });
    await service.markPaid(orders[0]!.cashfreeOrderId!, NOW);
    expect(spent).toHaveLength(0);
  });
});

/// The routes: the PAYMENTS_NOT_OFFERED gate before any offer is touched, and Play verify passing
/// what was bought on to the offer.
function controllerWith(cashfree: { mode: string; androidEnabled: boolean }) {
  const calls: unknown[][] = [];
  const offers = {
    startCheckout: (...a: unknown[]) => {
      calls.push(['checkout', ...a]);
      return Promise.resolve({ order_id: 'o1' });
    },
    markUsedByPlay: (...a: unknown[]) => {
      calls.push(['play', ...a]);
      return Promise.resolve(true);
    },
    forCaller: (_u: number, code: string) =>
      Promise.resolve({
        code,
        channel: code.startsWith('play') ? 'play' : 'cashfree',
      }),
  };
  const line = {
    productId: 'eatzify_premium',
    basePlanId: 'p3m',
    offerId: 'special',
  };
  const controller = new BillingController(
    {} as never,
    {} as never,
    { state: () => Promise.resolve({ tier: 'PRO' }) } as never,
    {} as never,
    {} as never,
    cashfree as never,
    { verify: () => Promise.resolve(line) } as never,
    {} as never,
    {} as never,
    offers as never,
    {} as never,
  );
  return { controller, calls, line };
}

const request = { user: { id: 7 } } as never;

describe('the offer routes', () => {
  it('should refuse checkout with PAYMENTS_NOT_OFFERED when android has no user choice billing', () => {
    const { controller, calls } = controllerWith({
      mode: 'production',
      androidEnabled: false,
    });
    expect(() =>
      controller.personalOfferCheckout(request, CODE, 'k', 'android'),
    ).toThrow(ForbiddenException);
    expect(calls).toHaveLength(0);
  });

  it('should check out when user choice billing is enabled on android', async () => {
    const { controller, calls } = controllerWith({
      mode: 'production',
      androidEnabled: true,
    });
    await controller.personalOfferCheckout(request, CODE, 'k', 'android');
    expect(calls[0]?.slice(0, 4)).toEqual(['checkout', 7, CODE, 'k']);
  });

  it('should pass the purchased line to the offer when verify carries a code', async () => {
    const { controller, calls, line } = controllerWith({
      mode: 'production',
      androidEnabled: false,
    });
    await controller.verifyPlay(request, {
      purchase_token: 't',
      offer_code: CODE,
    });
    expect(calls[0]?.slice(0, 4)).toEqual(['play', 7, CODE, line]);
  });

  it('should touch no offer when verify carries no code', async () => {
    const { controller, calls } = controllerWith({
      mode: 'production',
      androidEnabled: false,
    });
    await controller.verifyPlay(request, { purchase_token: 't' });
    expect(calls).toHaveLength(0);
  });
});

/// An offer opened on a phone that may not pay it is answered in words, not with a Buy button the
/// checkout would then refuse.
describe('opening an offer the app cannot pay', () => {
  const asUser = { user: { id: 7 } } as never;

  it('should refuse a cashfree offer on Android before User Choice Billing', async () => {
    const { controller } = controllerWith({
      mode: 'production',
      androidEnabled: false,
    });

    const refused = await errorOf(
      controller.personalOffer(asUser, 'cashfree-code-0000000', 'android'),
    );

    expect(refused.status).toBe(409);
    expect(refused.body.error.code).toBe('OFFER_NOT_PAYABLE');
    expect(refused.body.error.user_message).not.toMatch(/version of the app/);
  });

  it('should still show a Play offer there', async () => {
    const { controller } = controllerWith({
      mode: 'production',
      androidEnabled: false,
    });

    await expect(
      controller.personalOffer(asUser, 'play-code-00000000000', 'android'),
    ).resolves.toMatchObject({ channel: 'play' });
  });

  it('should show a cashfree offer once User Choice Billing is on', async () => {
    const { controller } = controllerWith({
      mode: 'production',
      androidEnabled: true,
    });

    await expect(
      controller.personalOffer(asUser, 'cashfree-code-0000000', 'android'),
    ).resolves.toMatchObject({ channel: 'cashfree' });
  });
});
