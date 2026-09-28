/// The public website: Terms, Privacy, Refunds & Cancellations and Contact live there, not in the
/// app, so the text a person agreed to and the text a payment gateway reviewed are the same page.
///
/// One host, one place. Override per build with `--dart-define=SITE_URL=https://…` (staging, or a
/// domain change) rather than editing strings across screens.
abstract final class SiteLinks {
  static const _base = String.fromEnvironment('SITE_URL', defaultValue: 'https://eatzify.zynthovo.com');

  static Uri get terms => Uri.parse('$_base/terms/');
  static Uri get privacy => Uri.parse('$_base/privacy/');
  static Uri get refunds => Uri.parse('$_base/refunds/');
  static Uri get contact => Uri.parse('$_base/contact/');
}
