import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/invoice.dart';
import 'package:health_pro/presentation/features/billing/invoices_controller.dart';
import 'package:health_pro/presentation/features/billing/invoices_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

/// D-255: the account's GST invoices, in all four states (rule 6).

final _rows = [
  Invoice(
    id: 'i2',
    number: 'CN2627-000001',
    isCreditNote: true,
    issuedAt: DateTime(2026, 10, 2),
    description: 'Eatzify Pro plan, 3 months',
    totalPaise: 99900,
  ),
  Invoice(
    id: 'i1',
    number: 'EZ2627-000001',
    isCreditNote: false,
    issuedAt: DateTime(2026, 9, 30),
    description: 'Eatzify Pro plan, 3 months',
    totalPaise: 99900,
  ),
];

Widget harness(FakeBillingRepository repo, {ThemeData? theme, double scale = 1}) {
  Get
    ..reset()
    ..put(InvoicesController(billing: repo));
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: GetMaterialApp(
      theme: theme ?? AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const InvoicesPage(),
    ),
  );
}

FakeBillingRepository withRows() => FakeBillingRepository()..invoiceResult = Right(_rows);

void main() {
  testWidgets('should list each invoice with its number and credit notes named', (tester) async {
    await tester.pumpWidget(harness(withRows()));
    await tester.pumpAndSettle();

    expect(find.text('Credit note'), findsOneWidget);
    expect(find.text('Eatzify Pro plan, 3 months'), findsOneWidget);
    expect(find.textContaining('EZ2627-000001'), findsOneWidget);
    expect(find.text('₹999'), findsNWidgets(2));
  });

  testWidgets('should say so when there are no invoices yet', (tester) async {
    await tester.pumpWidget(harness(FakeBillingRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No invoices yet'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets("should show the server's words when the list fails", (tester) async {
    final repo = FakeBillingRepository()
      ..invoiceResult = const Left(ApiFailure('Try later.', code: 'X', status: 503));
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Try later.'), findsOneWidget);
  });

  testWidgets('should show a skeleton while loading', (tester) async {
    await tester.pumpWidget(harness(withRows()));
    await tester.pumpAndSettle();
    Get.find<InvoicesController>().state.value = const Loading();
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.textContaining('EZ2627'), findsNothing);
  });

  testWidgets('it survives a 200 % font scale and dark mode', (tester) async {
    await tester.pumpWidget(harness(withRows(), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(harness(withRows(), theme: AppTheme.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
