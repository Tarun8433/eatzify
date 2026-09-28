import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/format/phone_e164.dart';

/// The bug this guards: sign-in stores `+91` + digits, the invite sheet sent the field's raw text,
/// and the server matches an invite to a client by EXACT phone equality. Inviting "8433145573"
/// wrote a row that the account `+918433145573` could never be shown.
void main() {
  test('should add the dial code to a bare local number', () {
    expect(PhoneE164.from('8433145573'), '+918433145573');
  });

  test('should agree with what sign-in stores for the same person', () {
    // Sign-in composes dialCode + digits. Every way of typing the same number must land there.
    const stored = '+918433145573';
    for (final typed in ['8433145573', '+918433145573', '918433145573', '08433145573']) {
      expect(PhoneE164.from(typed), stored, reason: 'typed as "$typed"');
    }
  });

  test('should ignore spaces, dashes and brackets', () {
    expect(PhoneE164.from(' 84331-45573 '), '+918433145573');
    expect(PhoneE164.from('+91 (843) 314-5573'), '+918433145573');
  });

  test('should read 00 as the written form of +', () {
    expect(PhoneE164.from('00918433145573'), '+918433145573');
  });

  test('should keep a number that already carries a different country code', () {
    expect(PhoneE164.from('+14155550123'), '+14155550123');
  });

  /// Null, not an empty string: the caller shows its own message rather than sending the server
  /// something it can only reject.
  test('should return null when there is nothing to send', () {
    expect(PhoneE164.from(''), isNull);
    expect(PhoneE164.from('   '), isNull);
    expect(PhoneE164.from('abc'), isNull);
  });

  group('showing a number back to somebody', () {
    test('should group an Indian number so it can be read at a glance', () {
      expect(PhoneE164.display('+918433145573'), '+91 84331 45573');
    });

    /// A row stored before the number was normalised must read the same as one stored after, or
    /// the same person appears twice in a list looking like two people.
    test('should read a bare local number the same as a normalised one', () {
      expect(PhoneE164.display('8433145573'), '+91 84331 45573');
    });

    /// Grouping only. A number this does not recognise is shown exactly as stored rather than
    /// chopped into groups that mean nothing.
    test('should leave anything else exactly as it is', () {
      expect(PhoneE164.display('+14155550123'), '+14155550123');
      expect(PhoneE164.display(''), '');
    });
  });
}
