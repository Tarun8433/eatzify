import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/paid_order.dart';
import 'package:health_pro/presentation/features/billing/payments_controller.dart';
import 'package:health_pro/presentation/features/billing/payments_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

/// Admin panel plan, Phase B: the person's payments and their refunds, in all four states.

PaidOrder order(String id, RefundOption refund, {bool refunded = false}) => PaidOrder(
  orderId: id,
  amountPaise: 64900,
  plan: 'PRO 3M',
  paidAt: DateTime(2026, 10, 2),
  refunded: refunded,
  refund: refund,
);

Widget harness(FakeBillingRepository repo, {double scale = 1}) {
  Get
    ..reset()
    ..put(PaymentsController(billing: repo));
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: GetMaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PaymentsPage(),
    ),
  );
}

AppLocalizations l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PaymentsPage)));

void main() {
  testWidgets('should show the empty state with a way to refresh when nothing was paid', (
    tester,
  ) async {
    await tester.pumpWidget(harness(FakeBillingRepository()));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text(l10n(tester).paymentsEmpty), findsOneWidget);
  });

  testWidgets('should show the server message when loading fails', (tester) async {
    final repo = FakeBillingRepository()
      ..paidOrderResult = const Left(ApiFailure('Could not load payments.', code: 'X'));
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();
    expect(find.byType(FailedView), findsOneWidget);
    expect(find.text('Could not load payments.'), findsOneWidget);
  });

  testWidgets('should name the plan in words and offer the refund the server allows', (
    tester,
  ) async {
    final repo = FakeBillingRepository()
      ..paidOrderResult = Right([
        order('a', RefundOption.selfServe),
        order('b', RefundOption.request),
        order('c', RefundOption.requested),
        order('d', RefundOption.none, refunded: true),
      ]);
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();
    final l = l10n(tester);

    expect(find.textContaining('PRO 3M'), findsNothing, reason: 'rule 4: no raw codes');
    expect(find.text(l.paymentsRefund), findsOneWidget);
    expect(find.text(l.paymentsRequestRefund), findsOneWidget);
    expect(find.text(l.paymentsRequested), findsOneWidget);
    expect(find.textContaining(l.paymentsRefunded), findsOneWidget);
  });

  testWidgets('should refund inside 7 days only after confirming', (tester) async {
    final repo = FakeBillingRepository()
      ..paidOrderResult = Right([order('a', RefundOption.selfServe)]);
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();
    final l = l10n(tester);

    await tester.tap(find.text(l.paymentsRefund));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.paymentsCancel));
    await tester.pumpAndSettle();
    expect(repo.refundCalls, isEmpty);

    await tester.tap(find.text(l.paymentsRefund));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.paymentsRefund));
    await tester.pumpAndSettle();
    expect(repo.refundCalls, ['refund:a']);
    expect(find.text(l.paymentsRefundDone), findsOneWidget);
  });

  testWidgets('should send a request with the reason typed, and not without one', (tester) async {
    final repo = FakeBillingRepository()
      ..paidOrderResult = Right([order('b', RefundOption.request)]);
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();
    final l = l10n(tester);

    await tester.tap(find.text(l.paymentsRequestRefund));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, l.paymentsSend);
    expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'a reason is needed');

    await tester.enterText(find.byType(TextField), 'Charged twice');
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(repo.refundCalls, ['request:b:Charged twice']);
  });

  testWidgets('should show a refused refund in the server words (rule 7)', (tester) async {
    final repo = FakeBillingRepository()
      ..paidOrderResult = Right([order('a', RefundOption.selfServe)])
      ..refundResult = const Left(ApiFailure('This payment is past the window.', code: 'X'));
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();
    final l = l10n(tester);

    await tester.tap(find.text(l.paymentsRefund));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.paymentsRefund));
    await tester.pumpAndSettle();
    expect(find.text('This payment is past the window.'), findsOneWidget);
  });

  testWidgets('should survive 200 % font scale (rule 12)', (tester) async {
    final repo = FakeBillingRepository()
      ..paidOrderResult = Right([
        order('a', RefundOption.selfServe),
        order('b', RefundOption.request),
      ]);
    await tester.pumpWidget(harness(repo, scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
