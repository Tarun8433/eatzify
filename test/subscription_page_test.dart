import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/presentation/features/billing/subscription_controller.dart';
import 'package:health_pro/presentation/features/billing/subscription_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';
import 'pumping.dart';

/// docs/11 §5–§7 on screen: what the plan is, when it renews, and the two things a person may do.

SubscriptionState plan({
  String tier = 'PRO',
  String status = 'active',
  bool autoRenew = true,
  bool requiresAfa = false,
  bool trialAvailable = false,
  DateTime? endsAt,
  DateTime? trialEndsAt,
}) => SubscriptionState(
  tier: tier,
  status: status,
  autoRenew: autoRenew,
  requiresAfa: requiresAfa,
  trialAvailable: trialAvailable,
  endsAt: endsAt ?? DateTime(2026, 12),
  startsAt: DateTime(2026, 6),
  trialEndsAt: trialEndsAt,
);

const free = SubscriptionState(tier: 'FREE', status: 'active', trialAvailable: true);

void main() {
  late FakeBillingRepository billing;

  setUp(() => billing = FakeBillingRepository());
  tearDown(Get.reset);

  Widget page({TextScaler scaler = TextScaler.noScaling}) {
    Get
      ..reset()
      ..put(SubscriptionController(billing: billing));
    return GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: const SubscriptionPage(),
      ),
    );
  }

  group('the four states', () {
    testWidgets('should wait behind a skeleton while the server answers', (tester) async {
      billing.hold = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();

      expect(find.byType(Skeleton), findsOneWidget);

      billing.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should render a failure with a retry', (tester) async {
      billing.subscriptionResult = const Left(OfflineFailure('You are offline.'));
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(find.text('You are offline.'), findsOneWidget);
    });

    testWidgets('should say FREE plainly, and offer the free week once', (tester) async {
      billing.subscriptionResult = const Right(free);
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Start your free week'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Cancel renewal'), findsNothing);
    });

    testWidgets('should name the tier and the renewal date', (tester) async {
      billing.subscriptionResult = Right(plan());
      await tester.pumpWidget(page());
      await settle(tester);

      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Renews on December 1, 2026'), findsOneWidget);
    });
  });

  testWidgets('should say a big plan renews with the bank’s approval (docs/11 §8)', (tester) async {
    billing.subscriptionResult = Right(plan(requiresAfa: true));
    await tester.pumpWidget(page());
    await settle(tester);

    expect(find.textContaining('bank will ask you to approve'), findsOneWidget);
  });

  testWidgets('should show a cancelled plan running to its end, with nothing to cancel', (
    tester,
  ) async {
    billing.subscriptionResult = Right(plan(autoRenew: false));
    await tester.pumpWidget(page());
    await settle(tester);

    expect(find.text('Runs until December 1, 2026, then stops'), findsOneWidget);
    expect(find.text('Cancel renewal'), findsNothing);
  });

  testWidgets('should not offer the free week to somebody who has used it', (tester) async {
    billing.subscriptionResult = const Right(SubscriptionState(tier: 'FREE', status: 'active'));
    await tester.pumpWidget(page());
    await settle(tester);

    expect(find.text('Start your free week'), findsNothing);
    expect(find.text('Your free week has been used.'), findsOneWidget);
  });

  testWidgets('should start the trial on the tier that was picked (docs/11 §6)', (tester) async {
    billing
      ..subscriptionResult = const Right(free)
      ..afterTrial = Right(
        plan(tier: 'BASIC', status: 'trialing', trialEndsAt: DateTime(2026, 9, 25)),
      );
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Basic'));
    await settle(tester);

    expect(billing.trialTiers, ['BASIC']);
    expect(find.text('Free trial until December 1, 2026'), findsOneWidget);
  });

  testWidgets('should say why the server refused, in its own words (rule 7)', (tester) async {
    billing
      ..subscriptionResult = const Right(free)
      ..afterTrial = const Left(
        ApiFailure('Your free trial has already been used.', code: 'TRIAL_ALREADY_USED'),
      );
    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pro'));
    await settle(tester);

    expect(find.text('Your free trial has already been used.'), findsOneWidget);
  });

  group('cancelling (docs/09 §7)', () {
    testWidgets('should ask first, and say what is kept', (tester) async {
      billing.subscriptionResult = Right(plan());
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.text('Cancel renewal'));
      await settle(tester);

      expect(find.text('Stop the renewal?'), findsOneWidget);
      expect(find.textContaining('You keep everything until December 1, 2026'), findsOneWidget);

      await tester.tap(find.text('Keep my plan'));
      await settle(tester);
      expect(billing.cancels, 0, reason: 'backing out cancels nothing');
    });

    testWidgets('should stop the renewal when it is confirmed', (tester) async {
      billing
        ..subscriptionResult = Right(plan())
        ..afterCancel = Right(plan(autoRenew: false));
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.text('Cancel renewal'));
      await settle(tester);
      await tester.tap(find.text('Stop renewing'));
      await settle(tester);

      expect(billing.cancels, 1);
      expect(find.text('Runs until December 1, 2026, then stops'), findsOneWidget);
    });
  });

  group('upgrading (docs/11 §7)', () {
    testWidgets('should show the arithmetic before anything is charged', (tester) async {
      billing
        ..subscriptionResult = Right(plan(tier: 'BASIC'))
        ..quoteResult = const Right(
          UpgradeQuote(
            tier: 'PRO',
            months: 3,
            pricePaise: 179900,
            creditPaise: 60000,
            amountDuePaise: 119900,
            remainingDays: 45,
            totalDays: 180,
          ),
        );
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.text('Upgrade to Pro'));
      await settle(tester);

      expect(find.text('₹1,799'), findsOneWidget);
      expect(find.text('− ₹600'), findsOneWidget);
      expect(find.text('₹1,199'), findsOneWidget);
      expect(find.textContaining('45 days left'), findsOneWidget);
      expect(billing.upgrades, isEmpty, reason: 'the quote charges nothing');
    });

    testWidgets('should charge the difference once it is confirmed', (tester) async {
      billing
        ..subscriptionResult = Right(plan(tier: 'BASIC'))
        ..quoteResult = const Right(
          UpgradeQuote(
            tier: 'PRO',
            months: 3,
            pricePaise: 179900,
            creditPaise: 179900,
            amountDuePaise: 0,
            remainingDays: 120,
            totalDays: 180,
          ),
        )
        ..afterUpgrade = Right(plan());
      await tester.pumpWidget(page());
      await settle(tester);

      await tester.tap(find.text('Upgrade to Pro'));
      await settle(tester);
      await tester.tap(find.text('Confirm upgrade'));
      await settle(tester);

      expect(billing.upgrades, [(tier: 'PRO', months: 3)]);
      // Nothing to pay, so the server settled it and the screen re-read the plan.
      expect(find.text('Pro'), findsOneWidget);
    });
  });

  testWidgets('should survive a 200 % text scale', (tester) async {
    billing.subscriptionResult = Right(plan(requiresAfa: true));
    await tester.pumpWidget(page(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
