/// The public website: Terms, Privacy, Refunds & Cancellations and Contact live there, not in the
/// app, so the text a person agreed to and the text a payment gateway reviewed are the same page.
///
/// One host, one place. Override per build with `--dart-define=SITE_URL=https://…` (staging, or a
/// domain change) rather than editing strings across screens.
abstract final class SiteLinks {
  static const _base = String.fromEnvironment('SITE_URL', defaultValue: 'https://www.eatzify.com');

  /// www.eatzify.com has no refunds page yet, so this one stays on the old site.
  // ponytail: move to $_base once the new site publishes refunds; Cashfree reviewed this URL.
  static const _refundsBase = 'https://eatzify.zynthovo.com';

  static Uri get terms => Uri.parse('$_base/terms-and-conditions.html');
  static Uri get privacy => Uri.parse('$_base/privacy-policy.html');
  static Uri get refunds => Uri.parse('$_refundsBase/refunds/');
  static Uri get contact => Uri.parse('$_base/help-support.html');
}
