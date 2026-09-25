import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

/// The paywall is the most layered thing in the app — two priced cards, a comparison table and a
/// pinned action inside one scrolling sheet — and `.claude/rules/testing.md` asks for a golden on
/// exactly that, at both text scales.
///
/// Regenerate with `flutter test --update-goldens test/paywall_golden_test.dart`.
Future<void> pumpSheet(WidgetTester tester, {required double textScale, ThemeData? theme}) async {
  final repo = FakeBillingRepository(priceRows: fullPriceMatrix);
  Get
    ..reset()
    ..put<BillingRepository>(repo, permanent: true);
  final controller = Get.put(BillingController(billing: repo), permanent: true);
  await controller.loadPrices();

  // Every style in AppTextStyles is wrapped in `GoogleFonts.inter`, which in a test would be an
  // HTTP fetch. It fails, falls back to the test default — Ahem — and the golden comes out as
  // rows of black boxes. Substituting a font `loadAppFonts` actually loaded is what makes the
  // image reviewable; metrics differ slightly from Inter, so this golden is a LAYOUT check.
  final base = theme ?? AppTheme.light;
  final withFont = base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto'));

  await tester.pumpWidget(
    GetMaterialApp(
      theme: withFont,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      // The sheet drawn as the page, so the golden is the sheet rather than a screenshot of the
      // scrim over whatever happened to be behind it.
      home: Scaffold(body: PaywallSheet(billing: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    // The theme asks google_fonts for Inter, which in a test means an HTTP fetch that cannot
    // happen. Without this the fetch throws and every styled run renders as Ahem boxes, so the
    // golden shows a layout nobody could review.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the paywall at 100 % text', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpSheet(tester, textScale: 1);
    await expectLater(find.byType(PaywallSheet), matchesGoldenFile('goldens/paywall_light.png'));
  });

  testWidgets('the paywall in dark mode', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpSheet(tester, textScale: 1, theme: AppTheme.dark);
    await expectLater(find.byType(PaywallSheet), matchesGoldenFile('goldens/paywall_dark.png'));
  });

  /// The compare table is below the fold on every phone, so a golden of the top of the sheet
  /// reviews everything except the half of the design that lists what the money buys.
  testWidgets('the compare table, scrolled to', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpSheet(tester, textScale: 1);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    await expectLater(find.byType(PaywallSheet), matchesGoldenFile('goldens/paywall_compare.png'));
  });

  /// Rule 12. At 200 % the cards stack rather than clip, which is the whole point of measuring the
  /// stack threshold against the scaled width.
  testWidgets('the paywall at 200 % text', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpSheet(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(PaywallSheet), matchesGoldenFile('goldens/paywall_large.png'));
  });
}
