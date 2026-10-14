/// D-266: Google Play / App Store purchase attempts, as the app reported how each one ended.

export type AttemptOutcome = 'cancelled' | 'failed' | 'pending' | 'purchased' | 'refused';

export type StoreAttempt = {
  id: string;
  user_id: number;
  user_name: string;
  email?: string | null;
  email_masked: string | null;
  /// Full only for a role allowed to see contact details; the API removes it otherwise (D-264).
  phone?: string | null;
  phone_masked: string | null;
  provider: 'play' | 'app_store';
  product_id: string;
  base_plan_id: string | null;
  offer_id: string | null;
  plan: string;
  outcome: AttemptOutcome;
  reason: string | null;
  store_code: string | null;
  created_at: string;
};

export const OUTCOME_LABEL: Record<AttemptOutcome, string> = {
  cancelled: 'Cancelled',
  failed: 'Failed',
  pending: 'Pending',
  purchased: 'Purchased',
  refused: 'Refused by server',
};

const storeName = (provider: StoreAttempt['provider']) => (provider === 'play' ? 'Play' : 'App Store');

/// The app's failure reason in plain words, with the store's own code after it: "Play couldn't
/// complete · BillingResponse.developerError". Empty when there is neither.
export function attemptDetail(a: Pick<StoreAttempt, 'provider' | 'reason' | 'store_code'>): string {
  const store = storeName(a.provider);
  const words: Record<string, string> = {
    storeUnavailable: `${store} not available on the phone`,
    productUnavailable: `Plan not on sale in ${store}`,
    alreadyOwned: 'Already owns this plan',
    storeBusy: `${store} busy or offline`,
    storeFailed: `${store} couldn't complete`,
    serverRefused: 'Server could not verify the purchase',
  };
  const reason = a.reason ? (words[a.reason] ?? a.reason) : null;
  return [reason, a.store_code].filter(Boolean).join(' · ');
}
