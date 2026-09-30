import { table, type Row } from './store-table';
import { StoreGrantService } from '../src/billing/store/store-grant.service';
import { PlayBillingService } from '../src/billing/store/play-billing.service';
import { PlayNotificationController } from '../src/billing/store/play-notification.controller';
import {
  grantFromPlay,
  gstSplitMicros,
  playProduct,
  storeAccountToken,
} from '../src/billing/store/store-rules';

/// Payments plan, Phase 4: Google Play purchases are checked with Google, claimed by one account,
/// and follow Google's state from then on.

const NOW = new Date('2026-10-01T10:00:00Z');
const LATER = '2026-11-01T10:00:00Z';
const PEPPER = 'test-pepper';

function purchase(over: Record<string, unknown> = {}) {
  return {
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
    lineItems: [
      {
        productId: 'pro',
        expiryTime: LATER,
        offerDetails: { basePlanId: 'p3m' },
        autoRenewingPlan: { autoRenewEnabled: true },
      },
    ],
    externalAccountIdentifiers: {
      obfuscatedExternalAccountId: storeAccountToken(1, PEPPER),
    },
    ...over,
  };
}

function playSetup(over: Record<string, unknown> = {}, rows: Row[] = []) {
  const subs = table(rows);
  const acks: string[] = [];
  const client = {
    configured: true,
    packageName: 'com.zynthovo.eatzify',
    subscription: () => Promise.resolve(purchase(over)),
    acknowledge: (_p: string, token: string) => {
      acks.push(token);
      return Promise.resolve();
    },
    reportExternalTransaction: (input: unknown): Promise<void> =>
      Promise.resolve(void input),
  };
  const config = { get: () => PEPPER };
  const service = new PlayBillingService(
    client as never,
    new StoreGrantService(subs as never),
    config as never,
  );
  return { service, subs, acks, client };
}

describe('Play purchase rules', () => {
  it('should map each subscription and base plan to a tier and length', () => {
    expect(playProduct('basic', 'p1m')).toEqual({
      tier: 'BASIC',
      duration: '1M',
    });
    expect(playProduct('pro', 'p1y')).toEqual({ tier: 'PRO', duration: '12M' });
    expect(playProduct('pro', 'p9m')).toBeNull();
    expect(playProduct('gold', 'p1m')).toBeNull();
  });

  it.each([
    ['SUBSCRIPTION_STATE_ACTIVE', 'active', true],
    ['SUBSCRIPTION_STATE_CANCELED', 'active', false],
    ['SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'grace', false],
    ['SUBSCRIPTION_STATE_ON_HOLD', 'past_due', false],
    ['SUBSCRIPTION_STATE_EXPIRED', 'expired', false],
  ])('should read %s as %s', (state, status, autoRenew) => {
    const grant = grantFromPlay('t', purchase({ subscriptionState: state }));
    expect(grant).toMatchObject({
      status,
      autoRenew,
      tier: 'PRO',
      duration: '3M',
    });
    expect(grant!.expiresAt.toISOString()).toBe(new Date(LATER).toISOString());
  });

  it('should grant nothing for a pending purchase — no money has moved', () => {
    expect(
      grantFromPlay(
        't',
        purchase({ subscriptionState: 'SUBSCRIPTION_STATE_PENDING' }),
      ),
    ).toBeNull();
  });

  it('should split GST out of an inclusive price, in micros', () => {
    expect(gstSplitMicros(64_900)).toEqual({
      preTaxMicros: String(55_000 * 10_000),
      taxMicros: String(9_900 * 10_000),
    });
  });
});

describe('Play verify and notifications', () => {
  it('should grant the plan Google reports and acknowledge it', async () => {
    const { service, subs, acks } = playSetup();
    await service.verify(1, 'tok-1', NOW);

    expect(subs.rows).toHaveLength(1);
    expect(subs.rows[0]).toMatchObject({
      userId: 1,
      tier: 'PRO',
      status: 'active',
      provider: 'play',
      providerRef: 'tok-1',
      priceKey: 'PRO:3M',
      autoRenew: true,
    });
    expect(acks).toEqual(['tok-1']);
  });

  it('should be idempotent: the same token twice is one row', async () => {
    const { service, subs } = playSetup();
    await service.verify(1, 'tok-1', NOW);
    await service.verify(1, 'tok-1', NOW);
    expect(subs.rows).toHaveLength(1);
  });

  it('should refuse a purchase made for another account', async () => {
    const { service, subs } = playSetup({
      externalAccountIdentifiers: {
        obfuscatedExternalAccountId: storeAccountToken(2, PEPPER),
      },
    });
    await expect(service.verify(1, 'tok-1', NOW)).rejects.toMatchObject({
      status: 409,
    });
    expect(subs.rows).toHaveLength(0);
  });

  it('should refuse a token another account already claimed', async () => {
    const { service } = playSetup({ externalAccountIdentifiers: {} }, [
      {
        id: 's1',
        userId: 2,
        provider: 'play',
        providerRef: 'tok-1',
        status: 'active',
      },
    ]);
    await expect(service.verify(1, 'tok-1', NOW)).rejects.toMatchObject({
      status: 409,
    });
  });

  it('should refuse a pending purchase without granting', async () => {
    const { service, subs } = playSetup({
      subscriptionState: 'SUBSCRIPTION_STATE_PENDING',
    });
    await expect(service.verify(1, 'tok-1', NOW)).rejects.toMatchObject({
      status: 422,
    });
    expect(subs.rows).toHaveLength(0);
  });

  it('should close a running trial when a store plan starts', async () => {
    const { service, subs } = playSetup({}, [
      {
        id: 's1',
        userId: 1,
        provider: null,
        providerRef: null,
        status: 'trialing',
        tier: 'PRO',
      },
    ]);
    await service.verify(1, 'tok-1', NOW);

    expect(subs.rows[0]).toMatchObject({
      status: 'cancelled',
      currentPeriodEnd: NOW,
    });
    expect(subs.rows[1]).toMatchObject({ status: 'active', provider: 'play' });
  });

  it('should follow an upgrade token onto the same row', async () => {
    const { service, subs } = playSetup({ linkedPurchaseToken: 'tok-1' }, [
      {
        id: 's1',
        userId: 1,
        provider: 'play',
        providerRef: 'tok-1',
        status: 'active',
      },
    ]);
    await service.verify(1, 'tok-2', NOW);
    expect(subs.rows).toHaveLength(1);
    expect(subs.rows[0].providerRef).toBe('tok-2');
  });

  it('should apply a notification to a claimed purchase, re-read from Google', async () => {
    const { service, subs } = playSetup(
      { subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' },
      [
        {
          id: 's1',
          userId: 1,
          provider: 'play',
          providerRef: 'tok-1',
          status: 'active',
        },
      ],
    );
    const data = Buffer.from(
      JSON.stringify({
        packageName: 'com.zynthovo.eatzify',
        subscriptionNotification: {
          purchaseToken: 'tok-1',
          notificationType: 13,
        },
      }),
    ).toString('base64');

    await service.notification({ message: { data } }, NOW);
    expect(subs.rows[0].status).toBe('expired');
  });

  it('should ignore a notification for a purchase nobody has claimed, or another app', async () => {
    const { service, subs } = playSetup();
    const note = (packageName: string) => ({
      message: {
        data: Buffer.from(
          JSON.stringify({
            packageName,
            subscriptionNotification: { purchaseToken: 'tok-9' },
          }),
        ).toString('base64'),
      },
    });
    await service.notification(note('com.zynthovo.eatzify'), NOW);
    await service.notification(note('com.someone.else'), NOW);
    await service.notification({ message: { data: 'not base64 json' } }, NOW);
    expect(subs.rows).toHaveLength(0);
  });

  it('should answer 503 before anything when Play is not configured', async () => {
    const { service, client } = playSetup();
    client.configured = false;
    await expect(service.verify(1, 'tok-1', NOW)).rejects.toMatchObject({
      status: 503,
    });
  });

  it('should report a Cashfree sale chosen through User Choice Billing', async () => {
    const { service, client } = playSetup();
    const reported: unknown[] = [];
    client.reportExternalTransaction = (input: unknown) => {
      reported.push(input);
      return Promise.resolve();
    };
    const order = { id: 'o1', amountPaise: '64900', paidAt: NOW };

    expect(
      await service.reportCashfreeSale({
        ...order,
        externalTransactionToken: null,
      }),
    ).toBe(false);
    expect(
      await service.reportCashfreeSale({
        ...order,
        externalTransactionToken: 'ext-1',
      }),
    ).toBe(true);
    expect(reported).toEqual([
      expect.objectContaining({ id: 'o1', externalTransactionToken: 'ext-1' }),
    ]);
  });
});

describe('Play notification endpoint', () => {
  const controller = (secret: string | null, seen: unknown[] = []) =>
    new PlayNotificationController(
      {
        notification: (b: unknown) => (seen.push(b), Promise.resolve()),
      } as never,
      { get: () => secret } as never,
    );

  it('should refuse a push without the shared secret', async () => {
    await expect(
      controller('s3cret').receive('wrong', {}),
    ).rejects.toMatchObject({ status: 401 });
    await expect(
      controller('s3cret').receive(undefined, {}),
    ).rejects.toMatchObject({ status: 401 });
    await expect(
      controller(null).receive('anything', {}),
    ).rejects.toMatchObject({ status: 401 });
  });

  it('should pass a push with the secret on', async () => {
    const seen: unknown[] = [];
    await controller('s3cret', seen).receive('s3cret', { message: {} });
    expect(seen).toHaveLength(1);
  });
});
