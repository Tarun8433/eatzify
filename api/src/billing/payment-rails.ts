import { CashfreeMode } from './cashfree.config';

/// Which app is asking, as it says in the `X-Client-Platform` header.
export type ClientPlatform = 'android' | 'ios' | 'unknown';

export function platformFrom(header: string | undefined): ClientPlatform {
  return header === 'android' || header === 'ios' ? header : 'unknown';
}

/**
 * Whether this app may be offered Cashfree for a subscription (D-249).
 *
 * - **iOS: never.** App Store guideline 3.1.1 requires Apple's in-app purchase for digital
 *   subscriptions, and India has no exemption.
 * - **Android: only once enrolled in Google Play's User Choice Billing.** Offering another
 *   processor for a digital subscription without it breaks Play's payments policy — and an app on
 *   open testing is reviewed against that policy.
 * - **An app that does not say what it is: no.** Builds from before this header existed are not
 *   offered a way to pay they may not be allowed to show.
 * - **Stub mode: always.** It moves no money, so no store rule applies, and it is how the purchase
 *   path is exercised before real credentials exist.
 */
export function cashfreeOffered(
  mode: CashfreeMode,
  platform: ClientPlatform,
  androidEnabled: boolean,
): boolean {
  if (mode === CashfreeMode.Stub) return true;
  return platform === 'android' && androidEnabled;
}

/// What `payments_mode` reports to an app that may not use Cashfree. The app draws no pay button.
export const PAYMENTS_UNAVAILABLE_MODE = 'unavailable';

/// Payments plan, Phase 4: Android pays through Google Play Billing where Cashfree is not offered.
export const PAYMENTS_PLAY_MODE = 'play';

/// Payments plan, Phase 5: an iPhone pays through Apple in-app purchase (guideline 3.1.1).
export const PAYMENTS_APP_STORE_MODE = 'app_store';

/// What `payments_mode` tells the app: Cashfree's mode where Cashfree is offered, Play on Android
/// where it is not and Play is configured, the App Store on an iPhone once it is configured,
/// otherwise nothing. Builds from before `play` existed
/// read an unknown mode as "no pay button", so this is safe to ship ahead of the app.
export function paymentsMode(
  mode: CashfreeMode,
  platform: ClientPlatform,
  androidEnabled: boolean,
  playConfigured: boolean,
  appStoreConfigured = false,
): string {
  if (cashfreeOffered(mode, platform, androidEnabled)) return mode;
  if (platform === 'android' && playConfigured) return PAYMENTS_PLAY_MODE;
  if (platform === 'ios' && appStoreConfigured) return PAYMENTS_APP_STORE_MODE;
  return PAYMENTS_UNAVAILABLE_MODE;
}
