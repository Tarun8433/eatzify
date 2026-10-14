import { randomBytes } from 'node:crypto';
import type { androidpublisher_v3 } from 'googleapis';
import {
  playProduct,
  type StoreDuration,
  type StoreTier,
} from '../store/store-rules';
import type { OfferChannel } from '../entities/personal-offer.entity';

/// D-265: what a personal offer is and when it may be used. Pure — no clock, no DB — so every
/// rule is table-tested; the service only fetches rows and applies these.

/// 16 random bytes = 128 bits, base64url → 22 characters. The link carries nothing else.
const CODE_BYTES = 16;

export function newOfferCode(): string {
  return randomBytes(CODE_BYTES).toString('base64url');
}

/// What the public link page accepts. Anything else gets the generic page, never an echo.
export const OFFER_CODE_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;

export const DEFAULT_EXPIRY_DAYS = 7;
export const MAX_EXPIRY_DAYS = 90;
const DAY_MS = 86_400_000;

export type OfferStatus = 'active' | 'used' | 'expired' | 'revoked';

type StatusFields = {
  expiresAt: Date;
  usedAt: Date | null;
  revokedAt: Date | null;
};

/// Revoked beats used beats expired: the admin's last word is what the dashboard should show.
export function offerStatus(offer: StatusFields, now: Date): OfferStatus {
  if (offer.revokedAt) return 'revoked';
  if (offer.usedAt) return 'used';
  if (offer.expiresAt <= now) return 'expired';
  return 'active';
}

/// The one question the app routes ask. Every "no" is answered with the same 404, so a code that
/// belongs to someone else is indistinguishable from one that never existed.
export function redeemableBy(
  offer: (StatusFields & { userId: number }) | null,
  userId: number,
  now: Date,
): boolean {
  return (
    offer !== null &&
    offer.userId === userId &&
    offerStatus(offer, now) === 'active'
  );
}

export type OfferRequest = {
  channel: OfferChannel;
  tier: StoreTier;
  duration: StoreDuration;
  amountPaise?: number;
  playProductId?: string;
  playBasePlanId?: string;
  playOfferId?: string;
  expiresInDays?: number;
};

/// Admin-facing refusals. The dashboard shows these verbatim.
export const OFFER_ERRORS = {
  playFieldsRequired:
    'A Google Play offer needs the product, base plan and offer from the Play catalogue.',
  playNoAmount:
    'A Google Play offer has no amount here — Play charges the price set in Play Console.',
  cashfreeAmountRequired:
    'A Cashfree offer needs an amount in paise greater than zero.',
  cashfreeNoPlayIds: 'A Cashfree offer cannot name a Google Play offer.',
  amountTooHigh:
    'The offer amount cannot be more than the normal price of that plan.',
  unknownPrice: 'That plan has no normal price, so it cannot be offered.',
  expiry: `Expiry must be a whole number of days from 1 to ${MAX_EXPIRY_DAYS}.`,
  notInCatalogue:
    'That Google Play offer is not active in Play Console for this plan. Pick one from the catalogue.',
} as const;

/// Cross-field rules the DTO cannot express. Returns the refusal, or null when the request holds.
/// `listPricePaise` is the plan's normal price (PriceService) — only Cashfree reads it.
export function offerRequestError(
  req: OfferRequest,
  listPricePaise: number | undefined,
): string | null {
  const days = req.expiresInDays ?? DEFAULT_EXPIRY_DAYS;
  if (!Number.isInteger(days) || days < 1 || days > MAX_EXPIRY_DAYS) {
    return OFFER_ERRORS.expiry;
  }

  const hasPlayIds = !!(
    req.playProductId ||
    req.playBasePlanId ||
    req.playOfferId
  );
  if (req.channel === 'play') {
    if (!req.playProductId || !req.playBasePlanId || !req.playOfferId) {
      return OFFER_ERRORS.playFieldsRequired;
    }
    return req.amountPaise === undefined ? null : OFFER_ERRORS.playNoAmount;
  }

  if (hasPlayIds) return OFFER_ERRORS.cashfreeNoPlayIds;
  const amount = req.amountPaise;
  if (amount === undefined || !Number.isInteger(amount) || amount <= 0) {
    return OFFER_ERRORS.cashfreeAmountRequired;
  }
  if (listPricePaise === undefined) return OFFER_ERRORS.unknownPrice;
  return amount > listPricePaise ? OFFER_ERRORS.amountTooHigh : null;
}

export function expiryFrom(now: Date, days = DEFAULT_EXPIRY_DAYS): Date {
  return new Date(now.getTime() + days * DAY_MS);
}

/// `https://api.example.com/offer/<code>` — the public page, outside the `/api` prefix.
export function offerLink(backendDomain: string, code: string): string {
  return `${backendDomain.replace(/\/+$/, '')}/offer/${code}`;
}

export type PlayCatalogueOffer = {
  product_id: string;
  base_plan_id: string;
  offer_id: string;
  tier: StoreTier;
  duration: StoreDuration;
  /// The first phase's INR price. Null when Play describes it some way we do not price here.
  price_paise: number | null;
  state: string;
};

const PAISE_PER_RUPEE = 100;
const NANOS_PER_PAISE = 10_000_000;

/// Play's `Money` (units + nanos) → integer paise. Null for anything that is not rupees.
export function moneyToPaise(
  money: androidpublisher_v3.Schema$Money | undefined,
): number | null {
  if (!money || money.currencyCode !== 'INR') return null;
  return (
    Number(money.units ?? 0) * PAISE_PER_RUPEE +
    Math.round((money.nanos ?? 0) / NANOS_PER_PAISE)
  );
}

function inr<T extends { regionCode?: string | null }>(
  configs: T[] | undefined,
): T | undefined {
  return configs?.find((c) => c.regionCode === 'IN');
}

/// What the first phase of an offer costs in India: a fixed price, free, or a percentage of the
/// base plan's own INR price. An absolute discount is prorated by Play over the phase, so it is
/// left unpriced (null) rather than guessed.
function offerPricePaise(
  offer: androidpublisher_v3.Schema$SubscriptionOffer,
  basePaise: number | null,
): number | null {
  const phase = inr(offer.phases?.[0]?.regionalConfigs);
  if (!phase) return null;
  if (phase.free) return 0;
  if (phase.price) return moneyToPaise(phase.price);
  if (phase.relativeDiscount != null && basePaise !== null) {
    return Math.round(basePaise * (1 - phase.relativeDiscount));
  }
  return null;
}

/// The admin's dropdown: ACTIVE offers on ACTIVE base plans whose product and base plan map to a
/// tier and duration (`playProduct`). An offer on an unmapped base plan is left out — the app could
/// not tell what it grants.
export function playCatalogue(
  subscriptions: androidpublisher_v3.Schema$Subscription[],
  offers: androidpublisher_v3.Schema$SubscriptionOffer[],
): PlayCatalogueOffer[] {
  const basePlans = new Map<string, androidpublisher_v3.Schema$BasePlan>();
  for (const s of subscriptions) {
    for (const p of s.basePlans ?? []) {
      if (s.productId && p.basePlanId)
        basePlans.set(`${s.productId}:${p.basePlanId}`, p);
    }
  }

  const out: PlayCatalogueOffer[] = [];
  for (const o of offers) {
    if (o.state !== 'ACTIVE' || !o.productId || !o.basePlanId || !o.offerId)
      continue;
    const plan = basePlans.get(`${o.productId}:${o.basePlanId}`);
    const product = playProduct(o.productId, o.basePlanId);
    if (plan?.state !== 'ACTIVE' || !product) continue;
    out.push({
      product_id: o.productId,
      base_plan_id: o.basePlanId,
      offer_id: o.offerId,
      ...product,
      price_paise: offerPricePaise(
        o,
        moneyToPaise(inr(plan.regionalConfigs)?.price),
      ),
      state: o.state,
    });
  }
  return out;
}

export type PlayLine = {
  productId: string | null;
  basePlanId: string | null;
  offerId: string | null;
};

/// A verified Play purchase redeems the offer only if it IS that offer, bought by its owner while
/// it was still live. Play enforced the price; this only decides whether to mark the link spent.
export function playPurchaseRedeems(
  offer:
    | (StatusFields & {
        userId: number;
        channel: OfferChannel;
        playProductId: string | null;
        playBasePlanId: string | null;
        playOfferId: string | null;
      })
    | null,
  userId: number,
  line: PlayLine,
  now: Date,
): boolean {
  return (
    redeemableBy(offer, userId, now) &&
    offer!.channel === 'play' &&
    !!line.offerId &&
    line.offerId === offer!.playOfferId &&
    line.productId === offer!.playProductId &&
    line.basePlanId === offer!.playBasePlanId
  );
}
