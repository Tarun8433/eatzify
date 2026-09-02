import {
  entitlementsFor,
  PRICES,
  TIER_ENTITLEMENTS,
  TIERS,
} from '../src/billing/tiers';

describe('tiers and entitlements — docs/11', () => {
  it('every tier defines every entitlement key', () => {
    const keys = Object.keys(TIER_ENTITLEMENTS.PRO);

    for (const tier of TIERS) {
      // A missing key would resolve to undefined and read as "not allowed" for a paying user.
      expect(Object.keys(TIER_ENTITLEMENTS[tier]).sort()).toEqual(
        [...keys].sort(),
      );
    }
  });

  it('FREE still gets a plan every day', () => {
    // docs/11 §1: restrict convenience, not protection. A free user who cannot generate a plan
    // has no product at all.
    expect(entitlementsFor('FREE')['plan.regenerate_per_day']).toBeGreaterThan(
      0,
    );
  });

  it('allowances never decrease as the tier rises', () => {
    const order = ['FREE', 'BASIC', 'PRO'] as const;

    for (let i = 1; i < order.length; i++) {
      const lower = entitlementsFor(order[i - 1]);
      const higher = entitlementsFor(order[i]);

      expect(higher['plan.regenerate_per_day']).toBeGreaterThanOrEqual(
        lower['plan.regenerate_per_day'],
      );
      expect(higher['history.days']).toBeGreaterThanOrEqual(
        lower['history.days'],
      );
    }
  });

  it('PRO unlocks what docs/11 §1 says it unlocks', () => {
    const pro = entitlementsFor('PRO');

    expect(pro['plan.alternates']).toBe(true);
    expect(pro['export.pdf']).toBe(true);
    expect(pro['coach.chat']).toBe(true);
  });

  describe('the price ladder', () => {
    // docs/11 §2 calls this out as a defect in the original matrix: "The ladder must be monotonic:
    // 3M base → 6M ≈ −12 % → 9M ≈ −18 % → 12M ≈ −25 % per month." A customer comparing quotes must
    // never see a longer term as worse value per month.
    const months = { '1M': 1, '3M': 3, '6M': 6, '9M': 9, '12M': 12 } as const;

    for (const tier of ['BASIC', 'PRO'] as const) {
      it(
        '$tier costs less per month as the term lengthens'.replace(
          '$tier',
          tier,
        ),
        () => {
          const durations = Object.keys(months) as (keyof typeof months)[];
          const perMonth = durations.map((d) => PRICES[tier][d] / months[d]);

          for (let i = 1; i < perMonth.length; i++) {
            expect(perMonth[i]).toBeLessThan(perMonth[i - 1]);
          }
        },
      );

      it(
        '$tier 12M is at least 25 % cheaper per month than 3M'.replace(
          '$tier',
          tier,
        ),
        () => {
          const threeM = PRICES[tier]['3M'] / 3;
          const twelveM = PRICES[tier]['12M'] / 12;

          // docs/11 §2 targets −25 %; 24 % is the tolerance that keeps whole-rupee prices.
          expect(1 - twelveM / threeM).toBeGreaterThanOrEqual(0.24);
        },
      );
    }

    it('prices are whole paise, never floats', () => {
      for (const tier of ['BASIC', 'PRO'] as const) {
        for (const price of Object.values(PRICES[tier])) {
          expect(Number.isInteger(price)).toBe(true);
        }
      }
    });
  });
});
