import { CashfreeMode } from '../src/billing/cashfree.config';
import { cashfreeOffered, platformFrom } from '../src/billing/payment-rails';

/// D-249: who may be offered Cashfree. Getting this wrong is a store policy breach on a public app,
/// so every cell of the table is pinned.
describe('payment rails — who may be offered Cashfree', () => {
  const live = [CashfreeMode.Sandbox, CashfreeMode.Production];

  it.each(live)('never on iPhone (%s), whatever the Android switch says', (mode) => {
    expect(cashfreeOffered(mode, 'ios', true)).toBe(false);
    expect(cashfreeOffered(mode, 'ios', false)).toBe(false);
  });

  it.each(live)('on Android (%s) only once User Choice Billing is approved', (mode) => {
    expect(cashfreeOffered(mode, 'android', false)).toBe(false);
    expect(cashfreeOffered(mode, 'android', true)).toBe(true);
  });

  it.each(live)('not to an app that does not say what it is (%s)', (mode) => {
    expect(cashfreeOffered(mode, 'unknown', true)).toBe(false);
  });

  it('always in stub mode, which moves no money', () => {
    for (const platform of ['android', 'ios', 'unknown'] as const) {
      expect(cashfreeOffered(CashfreeMode.Stub, platform, false)).toBe(true);
    }
  });

  it('reads only the two platforms it knows', () => {
    expect(platformFrom('android')).toBe('android');
    expect(platformFrom('ios')).toBe('ios');
    expect(platformFrom('Android')).toBe('unknown');
    expect(platformFrom(undefined)).toBe('unknown');
    expect(platformFrom('web')).toBe('unknown');
  });
});
