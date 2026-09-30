import {
  VerificationException,
  VerificationStatus,
} from '@apple/app-store-server-library';
import { AppStoreBillingService } from '../src/billing/store/app-store-billing.service';
import { StoreGrantService } from '../src/billing/store/store-grant.service';
import {
  PAYMENTS_APP_STORE_MODE,
  PAYMENTS_UNAVAILABLE_MODE,
  paymentsMode,
} from '../src/billing/payment-rails';
import { CashfreeMode } from '../src/billing/cashfree.config';
import {
  appStoreProducts,
  grantFromAppStore,
  storeAccountToken,
} from '../src/billing/store/store-rules';
import { table } from './store-table';

/// Payments plan, Phase 5: App Store purchases are checked against Apple's signature, re-read from
/// Apple, claimed by one account, and follow Apple's state from then on.

const NOW = new Date('2026-10-01T10:00:00Z');
const LATER = Date.parse('2026-11-01T10:00:00Z');
const PEPPER = 'test-pepper';

function tx(over: Record<string, unknown> = {}) {
  return {
    originalTransactionId: 'otx-1',
    productId: 'eatzify.pro.p3m',
    expiresDate: LATER,
    appAccountToken: storeAccountToken(1, PEPPER).toUpperCase(),
    ...over,
  };
}

function setup(
  opts: {
    over?: Record<string, unknown>;
    status?: number;
    autoRenew?: boolean;
    forged?: boolean;
    configured?: boolean;
  } = {},
) {
  const subs = table();
  const apple = {
    configured: opts.configured ?? true,
    verifyTransaction: () =>
      opts.forged
        ? Promise.reject(
            new VerificationException(VerificationStatus.VERIFICATION_FAILURE),
          )
        : Promise.resolve(tx(opts.over)),
    verifyNotification: () =>
      Promise.resolve({ data: { signedTransactionInfo: 'jws' } }),
    current: () =>
      Promise.resolve({
        transaction: tx(opts.over),
        status: opts.status ?? 1,
        autoRenew: opts.autoRenew ?? true,
      }),
  };
  const play = {
    accountToken: (userId: number) => storeAccountToken(userId, PEPPER),
  };
  const service = new AppStoreBillingService(
    apple as never,
    new StoreGrantService(subs as never),
    play as never,
  );
  return { service, subs };
}

describe('App Store purchase rules', () => {
  it('should name one product per tier and length', () => {
    const ids = appStoreProducts().map((p) => p.product_id);
    expect(ids).toHaveLength(8);
    expect(ids).toContain('eatzify.basic.p1m');
    expect(ids).toContain('eatzify.pro.p1y');
  });

  it('should make the account token a UUID Apple accepts', () => {
    expect(storeAccountToken(1, PEPPER)).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    expect(storeAccountToken(1, PEPPER)).toBe(storeAccountToken(1, PEPPER));
    expect(storeAccountToken(1, PEPPER)).not.toBe(storeAccountToken(2, PEPPER));
  });

  it.each([
    [1, 'active'],
    [2, 'expired'],
    [3, 'past_due'],
    [4, 'grace'],
    [5, 'expired'],
  ])('should map Apple status %i to %s', (status, expected) => {
    expect(grantFromAppStore(tx() as never, status, true)?.status).toBe(
      expected,
    );
  });

  it('should treat a revoked (refunded) transaction as expired', () => {
    const grant = grantFromAppStore(
      tx({ revocationDate: NOW.getTime() }) as never,
      1,
      true,
    );
    expect(grant).toMatchObject({ status: 'expired', autoRenew: false });
  });

  it('should grant nothing for a product it does not sell', () => {
    expect(
      grantFromAppStore(tx({ productId: 'eatzify.pro.p9m' }) as never, 1, true),
    ).toBeNull();
  });
});

describe('App Store verify and notifications', () => {
  it('should grant the plan Apple reports', async () => {
    const { service, subs } = setup();
    await service.verify(1, 'jws', NOW);

    expect(subs.rows).toHaveLength(1);
    expect(subs.rows[0]).toMatchObject({
      userId: 1,
      tier: 'PRO',
      status: 'active',
      provider: 'app_store',
      providerRef: 'otx-1',
      priceKey: 'PRO:3M',
      autoRenew: true,
    });
  });

  it('should be idempotent: the same transaction twice is one row', async () => {
    const { service, subs } = setup();
    await service.verify(1, 'jws', NOW);
    await service.verify(1, 'jws', NOW);
    expect(subs.rows).toHaveLength(1);
  });

  it('should refuse a forged or foreign transaction', async () => {
    const { service, subs } = setup({ forged: true });
    await expect(service.verify(1, 'jws', NOW)).rejects.toMatchObject({
      status: 422,
    });
    expect(subs.rows).toHaveLength(0);
  });

  it('should refuse a purchase made for another account', async () => {
    const { service, subs } = setup({
      over: { appAccountToken: storeAccountToken(2, PEPPER) },
    });
    await expect(service.verify(1, 'jws', NOW)).rejects.toMatchObject({
      status: 409,
    });
    expect(subs.rows).toHaveLength(0);
  });

  it('should refuse an expired subscription', async () => {
    const { service } = setup({ status: 2 });
    await expect(service.verify(1, 'jws', NOW)).rejects.toMatchObject({
      status: 422,
    });
  });

  it('should answer 503 when the App Store is not configured', async () => {
    const { service } = setup({ configured: false });
    await expect(service.verify(1, 'jws', NOW)).rejects.toMatchObject({
      status: 503,
    });
  });

  it('should follow a notification for a claimed purchase, not claim a new one', async () => {
    const { service, subs } = setup();
    await service.notification('payload', NOW);
    expect(subs.rows).toHaveLength(0);

    await service.verify(1, 'jws', NOW);
    const expired = setup({ status: 2 });
    expired.subs.rows.push(...subs.rows);
    await expired.service.notification('payload', NOW);
    expect(expired.subs.rows[0]).toMatchObject({ status: 'expired' });
  });
});

describe('App Store payment rail', () => {
  const PROD = CashfreeMode.Production;

  it('should send an iPhone to the App Store once it is configured', () => {
    expect(paymentsMode(PROD, 'ios', false, true, true)).toBe(
      PAYMENTS_APP_STORE_MODE,
    );
    expect(paymentsMode(PROD, 'ios', false, true, false)).toBe(
      PAYMENTS_UNAVAILABLE_MODE,
    );
  });

  it('should never send an Android phone to the App Store', () => {
    expect(paymentsMode(PROD, 'android', false, false, true)).toBe(
      PAYMENTS_UNAVAILABLE_MODE,
    );
  });
});
