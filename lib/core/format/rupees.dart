import 'package:intl/intl.dart';

/// Rupees, grouped the Indian way.
///
/// `ui-standards.md`: "Indian digit grouping for currency (₹1,24,560)" — thousands, then every two
/// digits after, not the western every-three. `en_IN` is what knows that; formatting a lakh with
/// the default locale prints ₹124,560, which reads as a different number to the people using this.
abstract final class Rupees {
  static final _format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static final _withPaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  static String format(int amount) => _format.format(amount);

  /// An amount in paise: whole rupees as [format] prints them, and the paise shown only when there
  /// are some. An admin may type ₹499.50 for a personal offer (D-265); printing ₹499 would
  /// understate the charge.
  static String fromPaise(int paise) =>
      paise % 100 == 0 ? format(paise ~/ 100) : _withPaise.format(paise / 100);
}
