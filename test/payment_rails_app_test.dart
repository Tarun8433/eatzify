import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/network/api_client.dart';
import 'package:health_pro/domain/entities/billing.dart';

import 'fakes.dart';
import 'paywall_sheet_test.dart' show openSheet;

/// D-249 from the app's side: where the server says no way to pay is offered, the app draws no pay
/// button — and nothing it does not recognise is ever read as permission to charge.
void main() {
  group('reading payments_mode', () {
    Entitlements mode(String m) => Entitlements.fromJson({'tier': 'FREE', 'payments_mode': m});

    test('should take payment only in a named live mode', () {
      expect(mode('sandbox').canTakePayment, isTrue);
      expect(mode('production').canTakePayment, isTrue);
      // The bug this fixes: "anything but stub" used to count as live.
      expect(mode('unavailable').canTakePayment, isFalse);
      expect(mode('some-mode-added-later').canTakePayment, isFalse);
    });

    test('should know stub from unavailable', () {
      expect(mode('stub').isStubPayments, isTrue);
      expect(mode('stub').paymentsUnavailable, isFalse);
      expect(mode('unavailable').paymentsUnavailable, isTrue);
      expect(mode('production').paymentsUnavailable, isFalse);
    });
  });

  testWidgets('should draw no pay button where payments are not offered', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(priceRows: fullPriceMatrix, paymentsMode: 'unavailable'),
    );

    expect(find.text('Choose a plan'), findsNothing);
    expect(find.textContaining('Pay '), findsNothing);
    // The plans and the honest note stay.
    expect(find.text('Payments are opening soon.'), findsOneWidget);
  });

  testWidgets('should still draw it in a live mode', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(priceRows: fullPriceMatrix, paymentsMode: 'production'),
    );

    expect(find.text('Payments are opening soon.'), findsNothing);
    expect(find.textContaining('Pay'), findsWidgets);
  });

  test('should tell the server which app is asking', () {
    final client = ApiClient(baseUrl: 'https://example.test');
    // flutter_test runs as Android unless told otherwise.
    expect(client.dio.options.headers['X-Client-Platform'], 'android');
  });
}
