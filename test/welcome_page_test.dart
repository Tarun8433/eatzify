import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/presentation/features/welcome/welcome_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// The intro carousel's layout (D-102 art direction).
///
/// The screen is nearly all decoration, so what is worth asserting is the part that can break
/// silently: that the claims are readable, and that none of the chrome — the curve, the medallion,
/// the three-column strip — overflows once the OS text setting grows.
Widget app() {
  Get.reset();
  putFakeSession();
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const WelcomePage(),
  );
}

AppLocalizations l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(WelcomePage)));

void main() {
  testWidgets('the first card states the claim and the three facts under it', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    final l = l10n(tester);

    expect(find.textContaining(l.welcomeSlide1Title, findRichText: true), findsOneWidget);
    expect(find.text(l.welcomeSlide1Body), findsOneWidget);
    for (final fact in [l.welcomeSlide1Fact1, l.welcomeSlide1Fact2, l.welcomeSlide1Fact3]) {
      expect(find.text(fact), findsOneWidget, reason: 'the strip says $fact');
    }
  });

  testWidgets('skip is offered on the way through and withdrawn on the last card', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    final l = l10n(tester);

    // Enabled while there is something to skip.
    expect(tester.widget<InkWell>(inkWellFor(l.welcomeSkip)).onTap, isNotNull);

    await tester.tap(find.text(l.welcomeNext));
    await settle(tester);
    await tester.tap(find.text(l.welcomeNext));
    await settle(tester);

    // Still in the tree on the last card — removing it would reflow the row under the thumb —
    // but no longer does anything, because the primary button now says the same thing.
    expect(find.text(l.welcomeSkip), findsOneWidget);
    expect(tester.widget<InkWell>(inkWellFor(l.welcomeSkip)).onTap, isNull);
    expect(find.text(l.welcomeStart), findsOneWidget);
  });

  testWidgets('the card survives 200 % font scale without clipping (rule 12)', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: app(),
      ),
    );
    await settle(tester);

    // A RenderFlex overflow throws into the test binding, so reaching here with the headline
    // present is the assertion — the slide scrolls rather than clips.
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder inkWellFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
