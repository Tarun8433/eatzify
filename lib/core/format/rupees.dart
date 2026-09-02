import 'package:intl/intl.dart';

/// Rupees, grouped the Indian way.
///
/// `ui-standards.md`: "Indian digit grouping for currency (₹1,24,560)" — thousands, then every two
/// digits after, not the western every-three. `en_IN` is what knows that; formatting a lakh with
/// the default locale prints ₹124,560, which reads as a different number to the people using this.
abstract final class Rupees {
  static final _format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static String format(int amount) => _format.format(amount);
}
