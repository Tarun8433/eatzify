import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/config/site_links.dart';
import 'package:health_pro/presentation/features/account/legal_links_card.dart';
import 'package:health_pro/presentation/widgets/site_link.dart';

import 'gym_fakes.dart';
import 'pumping.dart';

/// Every legal link has to land on its own page. A wrong target is invisible in review until a
/// person taps "Refunds" and reads the privacy policy — then it is the page they agreed to.
void main() {
  late List<Uri> opened;
  Future<bool> record(Uri uri) async {
    opened.add(uri);
    return true;
  }

  setUp(() => opened = []);

  testWidgets('should open each policy on its own page', (tester) async {
    await tester.pumpWidget(gymApp(Scaffold(body: LegalLinksCard(opener: record))));
    await settle(tester);

    for (final (label, uri) in [
      ('Terms & conditions', SiteLinks.terms),
      ('Privacy policy', SiteLinks.privacy),
      ('Refunds & cancellations', SiteLinks.refunds),
      ('Contact us', SiteLinks.contact),
    ]) {
      await tester.tap(find.text(label));
      await settle(tester);
      expect(opened.last, uri, reason: label);
    }
    expect(opened.toSet(), hasLength(4));
  });

  testWidgets('should put Terms and Refunds under the pay button', (tester) async {
    await tester.pumpWidget(
      gymApp(
        Scaffold(
          body: AgreementLine(
            lead: 'By paying, you agree to our',
            links: [
              (label: 'Terms & conditions', uri: SiteLinks.terms),
              (label: 'Refunds & cancellations', uri: SiteLinks.refunds),
            ],
            opener: record,
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Refunds & cancellations'));
    await settle(tester);
    expect(opened.single, SiteLinks.refunds);
  });

  testWidgets('should say so when a page cannot be opened', (tester) async {
    await tester.pumpWidget(gymApp(Scaffold(body: LegalLinksCard(opener: (_) async => false))));
    await settle(tester);

    await tester.tap(find.text('Terms & conditions'));
    await tester.pump();
    expect(
      find.text('Could not open the page. Check your connection and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('should keep 48 dp targets at 200 % text', (tester) async {
    await tester.pumpWidget(
      gymApp(
        Scaffold(
          body: AgreementLine(
            lead: 'By continuing, you agree to our',
            links: [
              (label: 'Terms & conditions', uri: SiteLinks.terms),
              (label: 'Privacy policy', uri: SiteLinks.privacy),
            ],
            opener: record,
          ),
        ),
        scaler: const TextScaler.linear(2),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextButton).first).height, greaterThanOrEqualTo(48));
  });

  test('should point every link at the one site', () {
    for (final uri in [SiteLinks.terms, SiteLinks.privacy, SiteLinks.contact]) {
      expect(uri.scheme, 'https');
      expect(uri.host, SiteLinks.terms.host);
    }
    // The new site has no refunds page yet; it stays on the page Cashfree reviewed.
    expect(SiteLinks.refunds.scheme, 'https');
  });
}
