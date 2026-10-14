import { inr } from './format';

/// D-265: the pure parts of the "Special offer" form, so they are tested without a browser.

export type PlayCatalogueOffer = {
  product_id: string;
  base_plan_id: string;
  offer_id: string;
  tier: 'BASIC' | 'PRO';
  duration: '1M' | '3M' | '6M' | '12M';
  price_paise: number | null;
  state: string;
};

export type PersonalOffer = {
  id: string;
  code: string;
  link: string;
  channel: 'play' | 'cashfree';
  tier: string;
  duration: string;
  amount_paise: number | null;
  play_offer_id: string | null;
  note: string | null;
  status: 'active' | 'used' | 'expired' | 'revoked';
  expires_at: string;
  created_at: string;
};

const TIER_LABEL: Record<string, string> = { BASIC: 'Basic', PRO: 'Pro' };

/// "1,299" or "1299.50" → paise as an integer, with no float arithmetic on the way. Null for
/// anything that is not a positive amount with at most two decimals.
export function rupeesToPaise(text: string): number | null {
  const clean = text.trim().replace(/,/g, '');
  const m = /^(\d+)(?:\.(\d{1,2}))?$/.exec(clean);
  if (!m) return null;
  const paise = Number(m[1]) * 100 + Number((m[2] ?? '').padEnd(2, '0'));
  return paise > 0 && Number.isSafeInteger(paise) ? paise : null;
}

/// "Pro 3M — ₹1,299 (winback-3m)", as the catalogue dropdown shows it.
export function catalogueLabel(o: PlayCatalogueOffer): string {
  const price = o.price_paise === null ? 'price set in Play' : inr(o.price_paise);
  return `${TIER_LABEL[o.tier] ?? o.tier} ${o.duration} — ${price} (${o.offer_id})`;
}

export function catalogueKey(o: PlayCatalogueOffer): string {
  return `${o.product_id}:${o.base_plan_id}:${o.offer_id}`;
}

export function whatsappLink(link: string): string {
  return `https://wa.me/?text=${encodeURIComponent(
    `Here is a special Eatzify offer for you. Open this link on your phone: ${link}`,
  )}`;
}

export const DEFAULT_EXPIRY_DAYS = 7;
export const MAX_EXPIRY_DAYS = 90;

/// Whole days 1–90, or null.
export function expiryDays(text: string): number | null {
  const n = Number(text.trim());
  return Number.isInteger(n) && n >= 1 && n <= MAX_EXPIRY_DAYS ? n : null;
}
