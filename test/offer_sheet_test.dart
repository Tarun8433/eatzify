import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/presentation/features/billing/offer_controller.dart';
import 'package:health_pro/presentation/features/billing/offer_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

const _code = 'Ab3_dE-f9GhIjKlMnOpQrS';

/// `GET /billing/offers/:code` as the contract spells it (D-265).
final _cashfree = PersonalOffer.fromJson(const {
  'code': _code,
  'channel': 'cashfree',
  'tier': 'PRO',
  'duration': '3M',
  'expires_at': '2026-10-21T12:00:00Z',
  'price_paise': 149900,
  'regular_price_paise': 179900,
  'play': null,
});

final _play = PersonalOffer.fromJson(const {
  'code': _code,
  'channel': 'play',
  'tier': 'PRO',
  'duration': '3M',
  'expires_at': '2026-10-21T12:00:00Z',
  'price_paise': null,
  'regular_price_paise': 179900,
  'play': {'product_id': 'pro', 'base_plan_id': 'p3m', 'offer_id': 'personal-399'},
});

/// A Cashfree checkout that stays open until the test closes it.
class _HeldGateway implements PaymentGateway {
  final done = Completer<PaymentResult>();
  int opens = 0;

  @override
  Future<PaymentResult> open({
    required String orderId,
    required String paymentSessionId,
    required String mode,
  }) {
    opens++;
    return done.future;
  }
}

void main() {
  late FakeBillingRepository repo;
  late OfferController controller;
  late int reloads;

  OfferController make({PaymentGateway? gateway, FakeStoreGateway? store}) =>
      controller = OfferController(
        code: _code,
        billing: repo,
        gateway: gateway,
        store: store,
        onPurchased: () async => reloads++,
      );

  Widget harness({double textScale = 1}) => GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    // Above the navigator, so the sheet's route gets it too.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => OfferSheet.show(context, controller),
          child: const Text('open'),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(harness(textScale: textScale));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapBuy(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Get this offer'));
    await tester.tap(find.text('Get this offer'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    Get.reset();
    repo = FakeBillingRepository(paymentsMode: 'production');
    reloads = 0;
    make();
  });

  group('states', () {
    testWidgets('should show a skeleton while the offer is loading', (tester) async {
      repo
        ..offerHold = Completer<void>()
        ..offerResult = Right(_cashfree);
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open'));
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.text('Get this offer'), findsNothing);

      repo.offerHold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
    });

    testWidgets('should show a Cashfree offer at the server amount, in rupees', (tester) async {
      repo.offerResult = Right(_cashfree);
      await open(tester);

      expect(find.text('A special offer for you'), findsOneWidget);
      expect(find.text('Pro · 3 Months'), findsOneWidget);
      expect(find.text('₹1,499'), findsOneWidget);
      // The regular price, struck through.
      final regular = tester.widget<Text>(find.text('₹1,799'));
      expect(regular.style?.decoration, TextDecoration.lineThrough);
      expect(find.text('Offer ends Oct 21, 2026'), findsOneWidget);
      expect(find.text('Get this offer'), findsOneWidget);
    });

    testWidgets("should show Play's own price for a Play offer", (tester) async {
      repo.offerResult = Right(_play);
      make(store: FakeStoreGateway()..price = '₹399');
      await open(tester);

      expect(find.text('₹399'), findsOneWidget);
      expect(find.text('₹1,799'), findsOneWidget);
      expect(find.text('Special price'), findsNothing);
    });

    testWidgets('should say "special price" when Play cannot name a figure', (tester) async {
      repo.offerResult = Right(_play);
      make(store: FakeStoreGateway());
      await open(tester);

      expect(find.text('Special price'), findsOneWidget);
    });

    testWidgets("should show the server's message and a Close when the offer is gone", (
      tester,
    ) async {
      // offerResult unset: the fake answers the contract's 404.
      await open(tester);

      expect(find.text('This offer has expired or is no longer available.'), findsOneWidget);
      expect(find.text('Get this offer'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('A special offer for you'), findsNothing);
    });
  });

  group('buying', () {
    testWidgets('should buy a Play offer by its offer id and hand over the offer code', (
      tester,
    ) async {
      repo
        ..offerResult = Right(_play)
        ..subscriptionResult = const Right(
          SubscriptionState(tier: 'FREE', status: 'active', storeAccountToken: 'acct-1'),
        );
      final store = FakeStoreGateway();
      make(store: store);
      await open(tester);
      await tapBuy(tester);

      expect(store.bought.single.productId, 'pro');
      expect(store.bought.single.basePlanId, 'p3m');
      expect(store.bought.single.accountToken, 'acct-1');
      expect(store.offers.single.offerId, 'personal-399');
      expect(store.offers.single.offerCode, _code);
      expect(reloads, 1, reason: 'entitlements are re-read, never assumed');
      expect(find.text('A special offer for you'), findsNothing, reason: 'the sheet closes');
    });

    testWidgets('should start an offer checkout with an idempotency key and open Cashfree', (
      tester,
    ) async {
      repo.offerResult = Right(_cashfree);
      final gateway = FakePaymentGateway();
      make(gateway: gateway);
      await open(tester);
      await tapBuy(tester);

      expect(repo.offerCheckouts.single.code, _code);
      expect(repo.offerCheckouts.single.idempotencyKey, isNotEmpty);
      expect(repo.bought, isEmpty, reason: 'not the plan checkout');
      expect(gateway.opened.single.sessionId, 'session_offer_1');
      expect(gateway.opened.single.mode, 'production');
      expect(reloads, 1);
    });

    testWidgets('should block a second tap while the checkout is open', (tester) async {
      repo.offerResult = Right(_cashfree);
      final gateway = _HeldGateway();
      make(gateway: gateway);
      await open(tester);

      await tester.tap(find.text('Get this offer'));
      await tester.pump();
      expect(find.text('Please wait…'), findsOneWidget);
      await tester.tap(find.text('Please wait…'));
      await tester.pump();

      expect(repo.offerCheckouts, hasLength(1));
      expect(gateway.opens, 1);

      gateway.done.complete(const PaymentResult.cancelled());
      await tester.pumpAndSettle();
      expect(controller.buying.value, isFalse);
    });

    testWidgets('should let the button be used again after the person cancels', (tester) async {
      repo
        ..offerResult = Right(_play)
        ..subscriptionResult = const Right(
          SubscriptionState(tier: 'FREE', status: 'active', storeAccountToken: 'acct-1'),
        );
      make(store: FakeStoreGateway(result: const PaymentResult.cancelled()));
      await open(tester);
      await tapBuy(tester);

      expect(controller.buying.value, isFalse);
      expect(find.text('Get this offer'), findsOneWidget, reason: 'still on the sheet, usable');
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Get this offer'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets("should show the gateway's words and reset after a failure", (tester) async {
      repo.offerResult = Right(_cashfree);
      make(
        gateway: FakePaymentGateway(
          result: const PaymentResult(PaymentOutcome.failed, message: 'Payment declined'),
        ),
      );
      await open(tester);
      await tapBuy(tester);

      expect(find.text('Payment declined'), findsOneWidget);
      expect(controller.buying.value, isFalse);
      expect(find.text('Get this offer'), findsOneWidget);
    });

    testWidgets("should show the server's refusal of the checkout verbatim", (tester) async {
      repo
        ..offerResult = Right(_cashfree)
        ..offerCheckoutFailure = const ApiFailure(
          'Payments are not available in this app yet.',
          code: 'PAYMENTS_NOT_OFFERED',
          status: 409,
        );
      make(gateway: FakePaymentGateway());
      await open(tester);
      await tapBuy(tester);

      expect(find.text('Payments are not available in this app yet.'), findsOneWidget);
      expect(controller.buying.value, isFalse);
    });

    testWidgets('should word a store failure in plain terms and reset', (tester) async {
      repo
        ..offerResult = Right(_play)
        ..subscriptionResult = const Right(
          SubscriptionState(tier: 'FREE', status: 'active', storeAccountToken: 'acct-1'),
        );
      make(
        store: FakeStoreGateway(
          result: const PaymentResult(
            PaymentOutcome.failed,
            reason: PaymentFailureReason.productUnavailable,
          ),
        ),
      );
      await open(tester);
      await tapBuy(tester);

      expect(controller.storeProblem.value, PaymentFailureReason.productUnavailable);
      expect(controller.buying.value, isFalse);
    });
  });

  testWidgets('should not overflow at 200 % text', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo.offerResult = Right(_cashfree);
    make(
      gateway: FakePaymentGateway(
        result: const PaymentResult(PaymentOutcome.failed, message: 'Payment declined'),
      ),
    );
    await open(tester, textScale: 2);
    await tapBuy(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Payment declined'), findsOneWidget);
  });

  test('should show paise only when an amount has some', () {
    expect(Rupees.fromPaise(149900), '₹1,499');
    expect(Rupees.fromPaise(49950), '₹499.50');
  });
}
