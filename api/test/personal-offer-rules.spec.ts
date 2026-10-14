import {
  DEFAULT_EXPIRY_DAYS,
  OFFER_CODE_PATTERN,
  OFFER_ERRORS,
  expiryFrom,
  moneyToPaise,
  newOfferCode,
  offerLink,
  offerRequestError,
  offerStatus,
  playCatalogue,
  playPurchaseRedeems,
  redeemableBy,
  type OfferRequest,
} from '../src/billing/offers/personal-offer-rules';
import {
  escapeHtml,
  offerIntentUrl,
  offerPage,
} from '../src/billing/offers/offer-page';
import { OfferPageController } from '../src/billing/offers/offer-page.controller';

/// D-265: personal offers. The rules are pure, so every case is a table row here.

const NOW = new Date('2026-10-14T10:00:00Z');
const LATER = new Date('2026-10-21T10:00:00Z');
const EARLIER = new Date('2026-10-01T10:00:00Z');

const live = {
  userId: 7,
  expiresAt: LATER,
  usedAt: null as Date | null,
  revokedAt: null as Date | null,
};

describe('offer codes', () => {
  it('should be 22 base64url characters when generated', () => {
    const code = newOfferCode();
    expect(code).toHaveLength(22);
    expect(code).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(OFFER_CODE_PATTERN.test(code)).toBe(true);
  });

  it('should never repeat when many are generated', () => {
    const codes = new Set(Array.from({ length: 5000 }, () => newOfferCode()));
    expect(codes.size).toBe(5000);
  });
});

describe('offer status', () => {
  it.each([
    ['active', live],
    ['expired', { ...live, expiresAt: EARLIER }],
    ['expired', { ...live, expiresAt: NOW }],
    ['used', { ...live, usedAt: EARLIER }],
    ['revoked', { ...live, revokedAt: EARLIER }],
    ['revoked', { ...live, usedAt: EARLIER, revokedAt: EARLIER }],
    ['used', { ...live, usedAt: EARLIER, expiresAt: EARLIER }],
  ])('should be %s when the row says so', (status, row) => {
    expect(offerStatus(row, NOW)).toBe(status);
  });
});

describe('who may open an offer', () => {
  it('should allow only the owner of a live offer', () => {
    expect(redeemableBy(live, 7, NOW)).toBe(true);
  });

  it.each([
    ['unknown', null, 7],
    ['another user', live, 8],
    ['expired', { ...live, expiresAt: EARLIER }, 7],
    ['used', { ...live, usedAt: EARLIER }, 7],
    ['revoked', { ...live, revokedAt: EARLIER }, 7],
  ])('should refuse when the offer is %s', (_why, offer, userId) => {
    expect(redeemableBy(offer, userId, NOW)).toBe(false);
  });
});

describe('validating a new offer', () => {
  const play: OfferRequest = {
    channel: 'play',
    tier: 'PRO',
    duration: '3M',
    playProductId: 'eatzify_premium',
    playBasePlanId: 'p3m',
    playOfferId: 'winback',
  };
  const cashfree: OfferRequest = {
    channel: 'cashfree',
    tier: 'PRO',
    duration: '3M',
    amountPaise: 99_900,
  };
  const LIST = 179_900;

  it('should accept a complete play offer when it names no amount', () => {
    expect(offerRequestError(play, LIST)).toBeNull();
  });

  it('should refuse a play offer when a play id is missing', () => {
    expect(offerRequestError({ ...play, playOfferId: undefined }, LIST)).toBe(
      OFFER_ERRORS.playFieldsRequired,
    );
  });

  it('should refuse a play offer when it carries an amount', () => {
    expect(offerRequestError({ ...play, amountPaise: 100 }, LIST)).toBe(
      OFFER_ERRORS.playNoAmount,
    );
  });

  it('should accept a cashfree offer when the amount is within the normal price', () => {
    expect(offerRequestError(cashfree, LIST)).toBeNull();
    expect(
      offerRequestError({ ...cashfree, amountPaise: LIST }, LIST),
    ).toBeNull();
  });

  it.each([
    [0, OFFER_ERRORS.cashfreeAmountRequired],
    [-5, OFFER_ERRORS.cashfreeAmountRequired],
    [10.5, OFFER_ERRORS.cashfreeAmountRequired],
    [undefined, OFFER_ERRORS.cashfreeAmountRequired],
    [LIST + 1, OFFER_ERRORS.amountTooHigh],
  ])('should refuse a cashfree amount of %s', (amountPaise, error) => {
    expect(offerRequestError({ ...cashfree, amountPaise }, LIST)).toBe(error);
  });

  it('should refuse a cashfree offer when it names a play offer', () => {
    expect(offerRequestError({ ...cashfree, playOfferId: 'x' }, LIST)).toBe(
      OFFER_ERRORS.cashfreeNoPlayIds,
    );
  });

  it('should refuse a cashfree offer when the plan has no price', () => {
    expect(offerRequestError(cashfree, undefined)).toBe(
      OFFER_ERRORS.unknownPrice,
    );
  });

  it.each([0, 91, 2.5])(
    'should refuse an expiry of %s days',
    (expiresInDays) => {
      expect(offerRequestError({ ...cashfree, expiresInDays }, LIST)).toBe(
        OFFER_ERRORS.expiry,
      );
    },
  );

  it('should default the expiry to 7 days when none is given', () => {
    expect(DEFAULT_EXPIRY_DAYS).toBe(7);
    expect(expiryFrom(NOW).toISOString()).toBe(LATER.toISOString());
  });
});

describe('the link', () => {
  it('should be the public page on the backend domain when built', () => {
    expect(offerLink('https://api.eatzify.app/', 'abcDEF123_-abcDEF123_')).toBe(
      'https://api.eatzify.app/offer/abcDEF123_-abcDEF123_',
    );
  });
});

describe('the link page', () => {
  const CODE = 'Zx9_-Zx9_-Zx9_-Zx9_-Zx';

  it('should redirect to the app intent with the code when the code is valid', () => {
    const html = offerPage(CODE);
    expect(offerIntentUrl(CODE)).toBe(
      `intent://offer/${CODE}#Intent;scheme=eatzify;package=com.zynthovo.eatzify;` +
        'S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.zynthovo.eatzify;end',
    );
    expect(html).toContain(`intent://offer/${CODE}#Intent;scheme=eatzify`);
    expect(html).toContain('http-equiv="refresh"');
    expect(html).toContain(
      'Open this link on your phone with Eatzify installed',
    );
  });

  it.each([
    'short',
    '<script>alert(1)</script>aaaaaaaaaa',
    '"><img src=x onerror=alert(1)>aaaa',
    'a'.repeat(65),
  ])('should show the generic page without echoing %s', (bad) => {
    const html = offerPage(bad);
    expect(html).not.toContain('intent://');
    expect(html).not.toContain(bad);
    expect(html).not.toContain('<img');
    expect(html).toContain(
      'Open this link on your phone with Eatzify installed',
    );
  });

  it('should escape every HTML metacharacter when escaping', () => {
    expect(escapeHtml(`<a href="x">'&'</a>`)).toBe(
      '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;',
    );
  });

  it('should serve html, uncached, without any lookup when the route is hit', () => {
    const headers = Reflect.getMetadata(
      '__headers__',
      OfferPageController.prototype.page,
    ) as { name: string; value: string }[];
    expect(headers).toEqual(
      expect.arrayContaining([
        { name: 'Content-Type', value: 'text/html; charset=utf-8' },
        { name: 'Cache-Control', value: 'no-store' },
      ]),
    );
    expect(new OfferPageController().page(CODE)).toBe(offerPage(CODE));
  });
});

describe('the play catalogue', () => {
  const inr = (units: string, nanos = 0) => ({
    currencyCode: 'INR',
    units,
    nanos,
  });
  const subscriptions = [
    {
      productId: 'eatzify_premium',
      basePlans: [
        {
          basePlanId: 'p3m',
          state: 'ACTIVE',
          regionalConfigs: [{ regionCode: 'IN', price: inr('1799') }],
        },
        { basePlanId: 'p6m', state: 'INACTIVE' },
      ],
    },
  ];
  const offer = (offerId: string, extra: object) => ({
    productId: 'eatzify_premium',
    basePlanId: 'p3m',
    offerId,
    state: 'ACTIVE',
    ...extra,
  });
  const phase = (config: object) => ({
    phases: [{ regionalConfigs: [{ regionCode: 'IN', ...config }] }],
  });

  it('should map an active offer to its tier, duration and INR price in paise', () => {
    const out = playCatalogue(subscriptions, [
      offer('special', phase({ price: inr('1299', 500_000_000) })),
    ]);
    expect(out).toEqual([
      {
        product_id: 'eatzify_premium',
        base_plan_id: 'p3m',
        offer_id: 'special',
        tier: 'PRO',
        duration: '3M',
        price_paise: 129_950,
        state: 'ACTIVE',
      },
    ]);
  });

  it('should price a percentage offer from the base plan and a free one at zero', () => {
    const out = playCatalogue(subscriptions, [
      offer('half', phase({ relativeDiscount: 0.5 })),
      offer('free', phase({ free: {} })),
      offer('abs', phase({ absoluteDiscount: inr('100') })),
    ]);
    expect(out.map((o) => [o.offer_id, o.price_paise])).toEqual([
      ['half', 89_950],
      ['free', 0],
      ['abs', null],
    ]);
  });

  it('should leave out inactive offers, inactive base plans and unmapped products', () => {
    const out = playCatalogue(subscriptions, [
      offer('draft', { state: 'INACTIVE' }),
      offer('on-inactive', { basePlanId: 'p6m' }),
      offer('unknown', { productId: 'other' }),
    ]);
    expect(out).toEqual([]);
  });

  it('should return no price when the money is not rupees', () => {
    expect(moneyToPaise({ currencyCode: 'USD', units: '5' })).toBeNull();
    expect(moneyToPaise(undefined)).toBeNull();
  });
});

describe('a play purchase redeeming an offer', () => {
  const offer = {
    ...live,
    channel: 'play' as const,
    playProductId: 'eatzify_premium',
    playBasePlanId: 'p3m',
    playOfferId: 'special',
  };
  const line = {
    productId: 'eatzify_premium',
    basePlanId: 'p3m',
    offerId: 'special',
  };

  it('should redeem when the purchased offer is this one and the owner bought it', () => {
    expect(playPurchaseRedeems(offer, 7, line, NOW)).toBe(true);
  });

  it.each([
    ['another offer id', offer, 7, { ...line, offerId: 'other' }],
    ['the base plan without an offer', offer, 7, { ...line, offerId: null }],
    ['another base plan', offer, 7, { ...line, basePlanId: 'p6m' }],
    ['another user', offer, 8, line],
    ['a used offer', { ...offer, usedAt: EARLIER }, 7, line],
    ['a cashfree offer', { ...offer, channel: 'cashfree' as const }, 7, line],
    ['no offer', null, 7, line],
  ])('should not redeem for %s', (_why, o, userId, l) => {
    expect(playPurchaseRedeems(o, userId, l, NOW)).toBe(false);
  });
});
