import { describe, expect, it } from 'vitest';
import {
  catalogueLabel,
  expiryDays,
  rupeesToPaise,
  whatsappLink,
} from '../lib/offer-form';

describe('rupeesToPaise', () => {
  it.each([
    ['1299', 129_900],
    ['1,299', 129_900],
    [' 1299.5 ', 129_950],
    ['0.01', 1],
    ['999.99', 99_999],
  ])('should convert %s rupees to integer paise', (text, paise) => {
    expect(rupeesToPaise(text)).toBe(paise);
  });

  it.each(['', '0', '0.00', '-5', 'abc', '12.345', '1e3'])(
    'should refuse %s when it is not a positive rupee amount',
    (text) => {
      expect(rupeesToPaise(text)).toBeNull();
    },
  );
});

describe('catalogueLabel', () => {
  const base = {
    product_id: 'eatzify_premium',
    base_plan_id: 'p3m',
    offer_id: 'winback-3m',
    tier: 'PRO' as const,
    duration: '3M' as const,
    state: 'ACTIVE',
  };

  it('should show tier, duration, price and offer id when the price is known', () => {
    expect(catalogueLabel({ ...base, price_paise: 129_900 })).toBe('Pro 3M — ₹1,299 (winback-3m)');
  });

  it('should say the price is set in Play when it is not known', () => {
    expect(catalogueLabel({ ...base, price_paise: null })).toBe(
      'Pro 3M — price set in Play (winback-3m)',
    );
  });
});

describe('whatsappLink', () => {
  it('should carry the encoded message with the link when built', () => {
    const url = whatsappLink('https://api.example.test/offer/abc_DEF-123');
    expect(url.startsWith('https://wa.me/?text=')).toBe(true);
    expect(decodeURIComponent(url.slice('https://wa.me/?text='.length))).toContain(
      'https://api.example.test/offer/abc_DEF-123',
    );
  });
});

describe('expiryDays', () => {
  it('should accept whole days from 1 to 90 when typed', () => {
    expect(expiryDays('7')).toBe(7);
    expect(expiryDays('90')).toBe(90);
  });

  it.each(['0', '91', '2.5', 'x'])('should refuse %s days', (text) => {
    expect(expiryDays(text)).toBeNull();
  });
});
