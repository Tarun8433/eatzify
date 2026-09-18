import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

late BillingController controller;

Widget harness(FakeBillingRepository repo, {ThemeData? theme}) {
  Get
    ..reset()
    ..put<BillingRepository>(repo, permanent: true);
  controller = Get.put(BillingController(billing: repo), permanent: true);
  return GetMaterialApp(
    theme: theme ?? AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => PaywallSheet.show(context, controller),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> openSheet(WidgetTester tester, FakeBillingRepository repo, {ThemeData? theme}) async {
  await tester.pumpWidget(harness(repo, theme: theme));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FakeBillingRepository get fullMatrix => FakeBillingRepository(priceRows: fullPriceMatrix);

/// How many cards actually SHOW the badge. Both cards build one — the unbadged card keeps its
/// space so the two price ladders start on the same line — so counting the text would count the
/// reserved one too.
int visibleBadges(WidgetTester tester) => tester
    .widgetList<Visibility>(
      find.ancestor(of: find.text('Most Popular'), matching: find.byType(Visibility)),
    )
    .where((v) => v.visible)
    .length;

void main() {
  /// CLAUDE.md rule 6. The sheet this replaced rendered a spinner whenever the list was empty, so
  /// a refused request and an empty catalogue were indistinguishable and neither ever resolved.
  group('the four states', () {
    testWidgets('a refused price list offers the server message and a retry', (tester) async {
      final repo = FakeBillingRepository(
        priceFailure: const ApiFailure('Could not load plans.', code: 'X', status: 500),
      );
      await openSheet(tester, repo);

      // Rule 7: the server's user_message verbatim, not copy written here.
      expect(find.text('Could not load plans.'), findsOneWidget);
      expect(find.byType(FailedView), findsOneWidget);
    });

    testWidgets('an empty catalogue says so rather than spinning', (tester) async {
      await openSheet(tester, FakeBillingRepository(priceRows: const []));

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a priced catalogue renders both tiers', (tester) async {
      await openSheet(tester, fullMatrix);

      expect(find.text('Basic'), findsWidgets);
      expect(find.text('Pro'), findsWidgets);
      expect(visibleBadges(tester), 1);
    });
  });

  /// The per-month line is DERIVED, and the derivation is the whole reason it can be wrong:
  /// ₹1,199 over six months is ₹199.83, which reads as ₹200. Integer division prints ₹199 and
  /// understates every longer term by a rupee.
  testWidgets('the per-month figure is rounded, not truncated', (tester) async {
    await openSheet(tester, fullMatrix);

    expect(find.text('₹200/month'), findsOneWidget); // BASIC 6M: 1,199 / 6
    expect(find.text('₹178/month'), findsOneWidget); // BASIC 9M: 1,599 / 9
    expect(find.text('₹467/month'), findsOneWidget); // PRO 6M: 2,799 / 6
    expect(find.text('₹199/month'), findsNothing);
  });

  testWidgets('the yearly view rereads the same prices without changing them', (tester) async {
    await openSheet(tester, fullMatrix);

    await tester.ensureVisible(find.text('Yearly View'));
    await tester.tap(find.text('Yearly View'));
    await tester.pumpAndSettle();

    // BASIC 3M is ₹699 a quarter, which is ₹2,796 a year — the price itself is untouched.
    expect(find.text('₹2,796/year'), findsOneWidget);
    expect(find.text('₹699'), findsOneWidget);
    expect(find.text('₹233/month'), findsNothing);
  });

  /// One selection across BOTH cards: somebody buys one tier for one duration, and two independent
  /// selections would leave the sheet showing two answers to one question.
  testWidgets('selecting in one card clears the selection in the other', (tester) async {
    await openSheet(tester, fullMatrix);

    // Opens on the first row the server sent.
    expect(controller.selectedTier.value, 'BASIC');
    expect(controller.selectedMonths.value, 1);

    await tester.ensureVisible(find.text('12 Months').last);
    await tester.tap(find.text('12 Months').last);
    await tester.pumpAndSettle();

    expect(controller.selectedTier.value, 'PRO');
    expect(controller.selectedMonths.value, 12);
    expect(controller.isSelected('BASIC', 1), isFalse);
  });

  /// The comparison table is the one place a paywall can promise something the backend does not
  /// enforce. Every row must be a key of `Entitlements` in `api/src/billing/tiers.ts`.
  group('the comparison table describes real entitlements', () {
    testWidgets('it names the gaps the backend actually has', (tester) async {
      await openSheet(tester, fullMatrix);
      await tester.scrollUntilVisible(find.text('Compare Features'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      expect(find.text('PDF export'), findsOneWidget);
      expect(find.text('Coach chat'), findsOneWidget);
      // The tiers differ by AMOUNT here, so the figure is the comparison, not a tick.
      expect(find.text('90 days'), findsOneWidget);
      expect(find.text('Unlimited'), findsOneWidget);
    });

    testWidgets('it promises nothing the tier table does not gate', (tester) async {
      await openSheet(tester, fullMatrix);
      await tester.scrollUntilVisible(find.text('Compare Features'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      // None of these is an entitlement key; a paywall that lists them is selling vapour.
      for (final invented in [
        'Ad-free experience',
        'Early access to new features',
        'Custom goals',
        'Advanced analytics',
      ]) {
        expect(find.text(invented), findsNothing, reason: '$invented is not in tiers.ts');
      }
    });
  });

  /// D-196. The button carries the PRICE, because "Continue" on a screen of ten prices is a
  /// button somebody taps to find out what it costs.
  testWidgets('the button names the price of the row that is selected', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(priceRows: fullPriceMatrix, paymentsMode: 'production'),
    );

    controller
      ..selectedTier.value = 'PRO'
      ..selectedMonths.value = 12;
    await tester.pumpAndSettle();

    expect(find.text('Pay ₹4,999'), findsOneWidget);
  });

  /// The sheet opens on the first row the server sent, so the button is priced from the moment it
  /// appears rather than reading "Choose a plan" above an already-ticked radio.
  testWidgets('it opens priced on the preselected row', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(priceRows: fullPriceMatrix, paymentsMode: 'production'),
    );

    // BASIC 1M, the first cell of the matrix.
    expect(find.text('Pay ₹249'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNotNull);
  });

  /// The dead-button path still has to exist: a catalogue that arrives with nothing selectable
  /// must not offer to charge for whichever row happened to be first.
  testWidgets('it asks for a choice when nothing is selected', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(priceRows: fullPriceMatrix, paymentsMode: 'production'),
    );

    controller
      ..selectedTier.value = null
      ..selectedMonths.value = null;
    await tester.pumpAndSettle();

    expect(find.text('Choose a plan'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull);
  });

  /// D-194's stub build. The label must not imply money moved, and the "opening soon" note stays
  /// up — it is true here and only here.
  testWidgets('a stub build says it is unlocking, not charging', (tester) async {
    await openSheet(tester, fullMatrix);

    controller
      ..selectedTier.value = 'PRO'
      ..selectedMonths.value = 12;
    await tester.pumpAndSettle();

    expect(find.text('Unlock for testing (₹4,999)'), findsOneWidget);
    expect(find.text('Payments are opening soon.'), findsOneWidget);
  });

  /// The other half of the same rule: a build that CAN take money must stop saying payments are
  /// coming soon.
  testWidgets('a live build drops the opening-soon note', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(priceRows: fullPriceMatrix, paymentsMode: 'production'),
    );

    expect(find.text('Payments are opening soon.'), findsNothing);
  });

  testWidgets('buying sends the selected row to the server', (tester) async {
    final repo = FakeBillingRepository(priceRows: fullPriceMatrix);
    await openSheet(tester, repo);

    controller
      ..selectedTier.value = 'BASIC'
      ..selectedMonths.value = 6;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(repo.bought, [(tier: 'BASIC', months: 6)]);
    // Stub mode stands in for the webhook, so the order is completed through the same path.
    expect(repo.completed, ['eatzify_test_1']);
  });

  /// Rule 7: the server's own words, never the app's summary of them.
  testWidgets('a refused purchase shows what the server said', (tester) async {
    await openSheet(
      tester,
      FakeBillingRepository(
        priceRows: fullPriceMatrix,
        paymentsMode: 'production',
        checkoutFailure: const ApiFailure(
          'You already have an active plan.',
          code: 'ALREADY_SUBSCRIBED',
          status: 422,
        ),
      ),
    );

    controller
      ..selectedTier.value = 'PRO'
      ..selectedMonths.value = 1;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(find.text('You already have an active plan.'), findsOneWidget);
  });

  /// Rule 12. The two cards sit side by side at 100 % and stack when each would fall under
  /// `AppSizes.tierCardMin` — which at 200 % text is on every phone.
  testWidgets('it survives a 200 % font scale without overflowing', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: harness(fullMatrix),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('it renders in dark mode without overflowing', (tester) async {
    await openSheet(tester, fullMatrix, theme: AppTheme.dark);

    expect(tester.takeException(), isNull);
    expect(visibleBadges(tester), 1);
  });
}
