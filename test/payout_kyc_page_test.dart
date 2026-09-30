import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/payout_kyc.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/payout_kyc_controller.dart';
import 'package:health_pro/presentation/features/coach/payout_kyc_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// D-255: the payout details form. The server is the real check; the form only catches typos.

class _FakeCoach implements CoachRepository {
  _FakeCoach({this.refusal});

  final Failure? refusal;
  final List<PayoutKycSubmission> sent = [];

  @override
  Future<Either<Failure, PayoutKyc>> submitPayoutKyc(PayoutKycSubmission details) async {
    sent.add(details);
    return refusal != null
        ? Left(refusal!)
        : const Right(PayoutKyc(required: false, status: 'pending', duePaise: 150000));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget harness(_FakeCoach coach, {ThemeData? theme, double scale = 1}) {
  Get
    ..reset()
    ..put(PayoutKycController(coach: coach));
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
      home: const PayoutKycPage(),
    ),
  );
}

Future<void> fill(WidgetTester tester, {String pan = 'abcde1234f'}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Test Partner');
  await tester.enterText(fields.at(1), pan);
  await tester.enterText(fields.at(2), '123456789012');
  await tester.enterText(fields.at(3), 'hdfc0001234');
}

Future<void> send(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Send for review'));
  await tester.tap(find.text('Send for review'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('should send the details upper-cased and trimmed', (tester) async {
    final coach = _FakeCoach();
    await tester.pumpWidget(harness(coach));
    await fill(tester);
    await send(tester);

    expect(coach.sent.single.pan, 'ABCDE1234F');
    expect(coach.sent.single.ifsc, 'HDFC0001234');
    expect(coach.sent.single.gstin, isNull);
  });

  testWidgets('should catch a mistyped PAN before sending', (tester) async {
    final coach = _FakeCoach();
    await tester.pumpWidget(harness(coach));
    await fill(tester, pan: 'ABC123');
    await send(tester);

    expect(coach.sent, isEmpty);
    expect(find.text('Please check this'), findsOneWidget);
  });

  testWidgets("should show the server's words when it refuses", (tester) async {
    final coach = _FakeCoach(
      refusal: const ApiFailure('Payout details cannot be saved right now.', code: 'X'),
    );
    await tester.pumpWidget(harness(coach));
    await fill(tester);
    await send(tester);

    expect(find.text('Payout details cannot be saved right now.'), findsOneWidget);
  });

  testWidgets('it survives a 200 % font scale and dark mode', (tester) async {
    await tester.pumpWidget(harness(_FakeCoach(), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(harness(_FakeCoach(), theme: AppTheme.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
