/// Turns what somebody typed into the E.164 string the server stores.
///
/// This exists because the two ends disagreed. Sign-in composes its number from a dial-code
/// picker (`+91` + digits), so an account is stored as `+918433145573`. The coach's invite sheet
/// sent the field's raw text, so inviting "8433145573" wrote that exact string — and the server
/// matches an invite to a client by EXACT phone equality, with no normalising of its own. The
/// result was an invite that existed in the database and could never be found by the person it
/// was for.
///
/// Deliberately not a phone-number library: the app takes one country's numbers today (docs/02),
/// and the job here is to agree with sign-in, not to validate the world's numbering plans.
abstract final class PhoneE164 {
  /// The dial code assumed when somebody types a bare local number. Matches sign-in's default.
  static const defaultDialCode = '+91';

  /// Returns null when [input] holds no digits at all — the caller shows its own "enter a number"
  /// message rather than sending an empty string the server would have to reject.
  static String? from(String input, {String dialCode = defaultDialCode}) {
    final trimmed = input.trim();
    // Everything a person puts between digits: spaces, dashes, brackets, dots.
    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;

    // Already written in full. Keep the typed digits rather than re-deriving them.
    if (trimmed.startsWith('+')) return '+$digits';

    // `00` is the other way to write `+` (ITU-T E.123), common on cards and in contact lists.
    if (digits.startsWith('00')) return '+${digits.substring(2)}';

    final code = dialCode.replaceAll(RegExp(r'[^\d]'), '');

    // A trunk prefix belongs to dialling inside the country, never to the stored number.
    final local = digits.startsWith('0') ? digits.replaceFirst(RegExp('^0+'), '') : digits;

    // Typed with the country code but no plus — "918433145573".
    if (local.startsWith(code) && local.length > code.length) return '+$local';

    return '$dialCode$local';
  }

  /// `+918433145573` -> `+91 84331 45573`, for showing a number back to somebody.
  ///
  /// Normalises first, so a row stored before [from] existed reads the same as one stored after
  /// it — the coach's invite list held `8433145573` and `+918433145573` for the same person, and
  /// showing one grouped and one not made them look like two people.
  ///
  /// Grouping only; never a different number. A coach scanning a list reads a grouped number at a
  /// glance and a 13-digit run character by character.
  static String display(String input) {
    final e164 = from(input) ?? input;
    final digits = e164.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length != 12 || !digits.startsWith('91')) return e164;

    final local = digits.substring(2);
    return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
  }
}
