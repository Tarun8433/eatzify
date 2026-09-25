import {
  AFA_THRESHOLD_PAISE,
  TRIAL_DAYS,
  isUpgrade,
  periodEnd,
  phoneHash,
  priceKeyFor,
  prorate,
  requiresAfa,
  trialEnd,
} from '../src/billing/subscription-rules';

/// docs/11 §6–§8. The money arithmetic, away from the database.

describe('proration on a mid-term upgrade (docs/11 §7)', () => {
  const bought = new Date('2026-01-01T00:00:00Z');
  const ends = new Date('2027-01-01T00:00:00Z'); // 365 days
  const hundredDaysIn = new Date('2026-04-11T00:00:00Z'); // 265 days left

  it('should credit the unused part of what was paid, and charge the rest', () => {
    const quote = prorate({
      paidPaise: 499_900,
      startsAt: bought,
      endsAt: ends,
      now: hundredDaysIn,
      newPricePaise: 599_900,
    });

    expect(quote.total_days).toBe(365);
    expect(quote.remaining_days).toBe(265);
    // floor(499900 × 265 / 365). docs/11 §7's worked example prints ₹3,679 for this case, which is
    // that formula over a 360-day year; the formula in the same section is the normative one and
    // this follows it (D-223).
    expect(quote.unused_paise).toBe(362_941);
    expect(quote.credit_paise).toBe(362_941);
    expect(quote.amount_due_paise).toBe(236_959);
  });

  it('should never hand money back: the credit stops at the new price', () => {
    const quote = prorate({
      paidPaise: 499_900,
      startsAt: bought,
      endsAt: ends,
      now: bought,
      newPricePaise: 249_900,
    });

    expect(quote.credit_paise).toBe(249_900);
    expect(quote.amount_due_paise).toBe(0);
  });

  it('should credit nothing for a period that has already run out', () => {
    const quote = prorate({
      paidPaise: 499_900,
      startsAt: bought,
      endsAt: ends,
      now: new Date('2027-06-01T00:00:00Z'),
      newPricePaise: 599_900,
    });

    expect(quote.remaining_days).toBe(0);
    expect(quote.credit_paise).toBe(0);
    expect(quote.amount_due_paise).toBe(599_900);
  });

  it('should credit nothing for a trial, because nobody paid for it', () => {
    const quote = prorate({
      paidPaise: 0,
      startsAt: bought,
      endsAt: ends,
      now: hundredDaysIn,
      newPricePaise: 599_900,
    });

    expect(quote.credit_paise).toBe(0);
    expect(quote.amount_due_paise).toBe(599_900);
  });

  it('should treat a subscription with no end date as nothing to credit', () => {
    const quote = prorate({
      paidPaise: 499_900,
      startsAt: bought,
      endsAt: null,
      now: hundredDaysIn,
      newPricePaise: 599_900,
    });

    expect(quote.total_days).toBe(0);
    expect(quote.credit_paise).toBe(0);
  });
});

describe('the RBI additional-factor threshold (docs/11 §8)', () => {
  it('should leave every BASIC and PRO cell on the silent renewal path', () => {
    expect(requiresAfa(499_900)).toBe(false);
    expect(requiresAfa(AFA_THRESHOLD_PAISE)).toBe(false);
  });

  it('should flag anything above ₹15,000, which renews with a prompt instead', () => {
    expect(requiresAfa(AFA_THRESHOLD_PAISE + 1)).toBe(true);
    expect(requiresAfa(2_000_000)).toBe(true);
  });
});

describe('periods', () => {
  it('should add the duration in months', () => {
    expect(
      periodEnd(new Date('2026-01-31T00:00:00Z'), '1M').toISOString(),
    ).toContain('2026-03-03');
    expect(
      periodEnd(new Date('2026-01-01T00:00:00Z'), '12M').toISOString(),
    ).toContain('2027-01-01');
  });

  it('should run a trial for exactly a week (docs/11 §6)', () => {
    const start = new Date('2026-09-18T10:00:00Z');
    expect(trialEnd(start).getTime() - start.getTime()).toBe(
      TRIAL_DAYS * 86_400_000,
    );
  });

  it('should name the cell a period was bought at', () => {
    expect(priceKeyFor('PRO', '3M')).toBe('PRO:3M');
  });
});

describe('which way a change goes (docs/11 §7)', () => {
  it('should call more expensive an upgrade and cheaper a downgrade', () => {
    expect(isUpgrade('BASIC', 'PRO')).toBe(true);
    expect(isUpgrade('FREE', 'BASIC')).toBe(true);
    expect(isUpgrade('PRO', 'BASIC')).toBe(false);
    expect(isUpgrade('PRO', 'PRO')).toBe(false);
  });
});

describe('the trial key (docs/11 §6)', () => {
  it('should be the same for the same number and never contain it', () => {
    const first = phoneHash('+919000000702', 'pepper');
    expect(phoneHash('+919000000702', 'pepper')).toBe(first);
    expect(first).not.toContain('9000000702');
    expect(first).toHaveLength(64);
  });

  it('should differ for another number, and for another pepper', () => {
    expect(phoneHash('+919000000703', 'pepper')).not.toBe(
      phoneHash('+919000000702', 'pepper'),
    );
    expect(phoneHash('+919000000702', 'other')).not.toBe(
      phoneHash('+919000000702', 'pepper'),
    );
  });
});
