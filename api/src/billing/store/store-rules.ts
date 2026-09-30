import { createHash } from 'crypto';
import type { androidpublisher_v3 } from 'googleapis';
import type { JWSTransactionDecodedPayload } from '@apple/app-store-server-library';

/// Payments plan, Phase 4: what a Google Play (and later App Store) purchase means for access.
/// Pure — no I/O — so every state a store can report is table-tested.

export type StoreTier = 'BASIC' | 'PRO';
export type StoreDuration = '1M' | '3M' | '6M' | '12M';
export type StoreProvider = 'play' | 'app_store';

/// What a verified store purchase grants. The store's own expiry is the truth for a store plan:
/// it renews, retries and refunds on its side, and this row follows.
export type StoreGrant = {
  provider: StoreProvider;
  /// Play: the purchase token. App Store: the original transaction id.
  ref: string;
  /// Play: the token this one replaced (an upgrade or a re-subscribe), so the row follows it.
  linkedRef: string | null;
  productId: string;
  tier: StoreTier;
  duration: StoreDuration;
  status: 'active' | 'grace' | 'past_due' | 'expired';
  expiresAt: Date;
  autoRenew: boolean;
  /// The account id the app attached at purchase, if any — see [storeAccountToken].
  accountToken: string | null;
  /// Play refunds a purchase not acknowledged within three days.
  needsAcknowledge: boolean;
};

/// Play Console: two subscriptions, `basic` and `pro`, each with these base plans.
const PLAY_BASE_PLANS: Record<string, StoreDuration> = {
  p1m: '1M',
  p3m: '3M',
  p6m: '6M',
  p1y: '12M',
};

export function playProduct(
  productId: string | null | undefined,
  basePlanId: string | null | undefined,
): { tier: StoreTier; duration: StoreDuration } | null {
  const tier =
    productId === 'basic' ? 'BASIC' : productId === 'pro' ? 'PRO' : null;
  const duration = basePlanId ? PLAY_BASE_PLANS[basePlanId] : undefined;
  return tier && duration ? { tier, duration } : null;
}

export type PlayProductView = {
  tier: StoreTier;
  duration: StoreDuration;
  product_id: string;
  base_plan_id: string;
};

/// The reverse of [playProduct]: what the app asks Play for, per cell of the price matrix. Sent
/// to the app so it never builds a product id itself.
export function playProducts(): PlayProductView[] {
  return (['BASIC', 'PRO'] as const).flatMap((tier) =>
    Object.entries(PLAY_BASE_PLANS).map(([basePlanId, duration]) => ({
      tier,
      duration,
      product_id: tier.toLowerCase(),
      base_plan_id: basePlanId,
    })),
  );
}

/// Play's `subscriptionState` → our lifecycle (docs/11 §5). Pending purchases grant nothing: the
/// money has not moved. On hold and paused keep the row but not the access.
const PLAY_STATES: Record<string, StoreGrant['status'] | null> = {
  SUBSCRIPTION_STATE_ACTIVE: 'active',
  // Cancelled means "will not renew" — access runs to the expiry already paid for.
  SUBSCRIPTION_STATE_CANCELED: 'active',
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: 'grace',
  SUBSCRIPTION_STATE_ON_HOLD: 'past_due',
  SUBSCRIPTION_STATE_PAUSED: 'past_due',
  SUBSCRIPTION_STATE_EXPIRED: 'expired',
  SUBSCRIPTION_STATE_PENDING: null,
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: null,
};

export function grantFromPlay(
  token: string,
  purchase: androidpublisher_v3.Schema$SubscriptionPurchaseV2,
): StoreGrant | null {
  const status = PLAY_STATES[purchase.subscriptionState ?? ''] ?? null;
  const item = purchase.lineItems?.[0];
  const product = playProduct(item?.productId, item?.offerDetails?.basePlanId);
  const expiresAt = item?.expiryTime ? new Date(item.expiryTime) : null;
  if (!status || !product || !item?.productId || !expiresAt) return null;

  return {
    provider: 'play',
    ref: token,
    linkedRef: purchase.linkedPurchaseToken ?? null,
    productId: item.productId,
    ...product,
    status,
    expiresAt,
    autoRenew:
      purchase.subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE' &&
      item.autoRenewingPlan?.autoRenewEnabled !== false,
    accountToken:
      purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    needsAcknowledge:
      purchase.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' &&
      status !== 'expired',
  };
}

/// The id the app attaches to a store purchase (Play `obfuscatedAccountId`, Apple
/// `appAccountToken`), so a purchase token cannot be replayed onto another account. A keyed hash
/// of the user id: stable, and it tells Google and Apple nothing about who the person is.
/// UUID-shaped (v4 bits set) because Apple accepts nothing else; Play takes any string.
export function storeAccountToken(userId: number, pepper: string): string {
  const h = createHash('sha256')
    .update(`store-account:${pepper}:${userId}`)
    .digest('hex');
  const variant = ((parseInt(h[16], 16) & 0x3) | 0x8).toString(16);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-${variant}${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

/// Payments plan, Phase 5: App Store Connect, one subscription group, one product per cell.
/// Apple has no base plans, so the length is in the product id.
const APP_STORE_PRODUCTS: Record<
  string,
  { tier: StoreTier; duration: StoreDuration }
> = Object.fromEntries(
  (['BASIC', 'PRO'] as const).flatMap((tier) =>
    Object.entries(PLAY_BASE_PLANS).map(([plan, duration]) => [
      `eatzify.${tier.toLowerCase()}.${plan}`,
      { tier, duration },
    ]),
  ),
);

export type AppStoreProductView = {
  tier: StoreTier;
  duration: StoreDuration;
  product_id: string;
};

/// What the app asks StoreKit for, per cell of the price matrix.
export function appStoreProducts(): AppStoreProductView[] {
  return Object.entries(APP_STORE_PRODUCTS).map(([productId, p]) => ({
    ...p,
    product_id: productId,
  }));
}

/// Apple's subscription `status` (App Store Server API) → our lifecycle (docs/11 §5).
const APP_STORE_STATES: Record<number, StoreGrant['status']> = {
  1: 'active',
  2: 'expired',
  3: 'past_due', // billing retry: Apple is still trying, no access
  4: 'grace', // billing grace period: access continues
  5: 'expired', // revoked (refund, or Family Sharing removed)
};

/// A verified App Store transaction plus Apple's current status for it → what it grants.
export function grantFromAppStore(
  tx: JWSTransactionDecodedPayload,
  status: number | undefined,
  autoRenew: boolean,
): StoreGrant | null {
  const product = tx.productId ? APP_STORE_PRODUCTS[tx.productId] : undefined;
  const mapped = status === undefined ? undefined : APP_STORE_STATES[status];
  if (!product || !mapped || !tx.originalTransactionId || !tx.expiresDate) {
    return null;
  }

  const revoked = !!tx.revocationDate;
  return {
    provider: 'app_store',
    ref: tx.originalTransactionId,
    linkedRef: null,
    productId: tx.productId!,
    ...product,
    status: revoked ? 'expired' : mapped,
    expiresAt: new Date(tx.expiresDate),
    autoRenew: !revoked && mapped === 'active' && autoRenew,
    // Apple returns the UUID in whatever case it likes; ours is lowercase.
    accountToken: tx.appAccountToken?.toLowerCase() ?? null,
    // Apple has no acknowledge step; the app finishes the transaction itself.
    needsAcknowledge: false,
  };
}

/// Prices are GST-inclusive (docs/11 §2); Play's external-transaction report wants the tax apart.
const GST_PERCENT = 18;
const MICROS_PER_PAISE = 10_000;

export function gstSplitMicros(amountPaise: number): {
  preTaxMicros: string;
  taxMicros: string;
} {
  const preTaxPaise = Math.round((amountPaise * 100) / (100 + GST_PERCENT));
  return {
    preTaxMicros: String(preTaxPaise * MICROS_PER_PAISE),
    taxMicros: String((amountPaise - preTaxPaise) * MICROS_PER_PAISE),
  };
}
