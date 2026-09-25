import { resolveMode, CashfreeMode } from '../src/billing/cashfree.config';

/// D-197. `CASHFREE_MODE` and `CASHFREE_ENVIRONMENT` are one setting. Cashfree's dashboard calls
/// it the environment, so that is the name people write — and a variable that looks like it turned
/// on live payments while being ignored is the worst kind of config bug.

describe('deciding whether this build charges real cards', () => {
  it('should default to the mode that takes no money', () => {
    expect(resolveMode({})).toBe(CashfreeMode.Stub);
  });

  it('should accept the setting under either name', () => {
    expect(resolveMode({ CASHFREE_MODE: 'production' })).toBe(
      CashfreeMode.Production,
    );
    expect(resolveMode({ CASHFREE_ENVIRONMENT: 'production' })).toBe(
      CashfreeMode.Production,
    );
  });

  it('should accept both names when they agree', () => {
    expect(
      resolveMode({
        CASHFREE_MODE: 'sandbox',
        CASHFREE_ENVIRONMENT: 'sandbox',
      }),
    ).toBe(CashfreeMode.Sandbox);
  });

  /**
   * The case this function exists for.
   *
   * Two lines in one file saying different things about whether a real card is charged, with a
   * precedence rule deciding it silently. Refusing is the only answer that cannot be wrong.
   */
  it('should refuse when the two names disagree', () => {
    expect(() =>
      resolveMode({
        CASHFREE_MODE: 'stub',
        CASHFREE_ENVIRONMENT: 'production',
      }),
    ).toThrow(/disagree/);
  });

  it('should name both values so the wrong line can be found', () => {
    expect(() =>
      resolveMode({
        CASHFREE_MODE: 'stub',
        CASHFREE_ENVIRONMENT: 'production',
      }),
    ).toThrow(/CASHFREE_MODE=stub.*CASHFREE_ENVIRONMENT=production/);
  });
});
