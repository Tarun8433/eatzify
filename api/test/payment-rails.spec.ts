import { CashfreeMode } from '../src/billing/cashfree.config';
import {
  cashfreeOffered,
  PAYMENTS_UNAVAILABLE_MODE,
  paymentsMode,
  platformFrom,
} from '../src/billing/payment-rails';
import { playProduct, playProducts } from '../src/billing/store/store-rules';

/// D-249: who may be offered Cashfree. Getting this wrong is a store policy breach on a public app,
/// so every cell of the table is pinned.
describe('payment rails — who may be offered Cashfree', () => {
  const live = [CashfreeMode.Sandbox, CashfreeMode.Production];

  it.each(live)(
    'never on iPhone (%s), whatever the Android switch says',
    (mode) => {
      expect(cashfreeOffered(mode, 'ios', true)).toBe(false);
      expect(cashfreeOffered(mode, 'ios', false)).toBe(false);
    },
  );

  it.each(live)(
    'on Android (%s) only once User Choice Billing is approved',
    (mode) => {
      expect(cashfreeOffered(mode, 'android', false)).toBe(false);
      expect(cashfreeOffered(mode, 'android', true)).toBe(true);
    },
  );

  it.each(live)('not to an app that does not say what it is (%s)', (mode) => {
    expect(cashfreeOffered(mode, 'unknown', true)).toBe(false);
  });

  it('should offer it always in stub mode, which moves no money', () => {
    for (const platform of ['android', 'ios', 'unknown'] as const) {
      expect(cashfreeOffered(CashfreeMode.Stub, platform, false)).toBe(true);
    }
  });

  it('should read only the two platforms it knows', () => {
    expect(platformFrom('android')).toBe('android');
    expect(platformFrom('ios')).toBe('ios');
    expect(platformFrom('Android')).toBe('unknown');
    expect(platformFrom(undefined)).toBe('unknown');
    expect(platformFrom('web')).toBe('unknown');
  });
});

/// Payments plan, Phase 4: what `payments_mode` tells the app to draw.
describe('payment rails — which way to pay', () => {
  const PROD = CashfreeMode.Production;

  it('should send Android to Google Play when Cashfree is not offered there', () => {
    expect(paymentsMode(PROD, 'android', false, true)).toBe('play');
  });

  it('should keep Cashfree on Android when User Choice Billing is approved', () => {
    expect(paymentsMode(PROD, 'android', true, true)).toBe(PROD);
  });

  it('should offer nothing on Android when Play is not configured either', () => {
    expect(paymentsMode(PROD, 'android', false, false)).toBe(
      PAYMENTS_UNAVAILABLE_MODE,
    );
  });

  it('should never send an iPhone or an unnamed app to Play', () => {
    expect(paymentsMode(PROD, 'ios', false, true)).toBe(
      PAYMENTS_UNAVAILABLE_MODE,
    );
    expect(paymentsMode(PROD, 'unknown', false, true)).toBe(
      PAYMENTS_UNAVAILABLE_MODE,
    );
  });

  it('should stay in stub everywhere when in stub mode', () => {
    expect(paymentsMode(CashfreeMode.Stub, 'android', false, true)).toBe(
      CashfreeMode.Stub,
    );
  });

  it('should list every Play product the verify route can read back', () => {
    const products = playProducts();
    expect(products).toHaveLength(8);
    for (const p of products) {
      expect(playProduct(p.product_id, p.base_plan_id)).toEqual({
        tier: p.tier,
        duration: p.duration,
      });
    }
  });
});
