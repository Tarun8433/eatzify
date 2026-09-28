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
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/coach_you_tab.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// D-174 and docs/12 §6. Where a partner stands, and the way back to their own account — the tab
/// never claims verified, because that is an admin's decision (docs/09 §9).

class _FakeCoach implements CoachRepository {
  Either<Failure, CoachApplication?>? result;
  Completer<void>? hold;

  /// What `acceptCoachingAgreement` answers with — the server decides the level, not the app.
  CoachApplication? afterCoaching;
  final coachingVersions = <String>[];

  @override
  Future<Either<Failure, CoachApplication?>> application() async {
    await hold?.future;
    return result ?? const Right(null);
  }

  @override
  Future<Either<Failure, CoachApplication>> acceptCoachingAgreement(String version) async {
    coachingVersions.add(version);
    return Right(afterCoaching!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

CoachApplication applicationWith({
  String status = 'submitted',
  int level = 1,
  bool coachingAgreementAccepted = false,
}) => CoachApplication(
  status: status,
  level: level,
  agreementAccepted: true,
  hasIdDocument: true,
  hasQualificationDocument: false,
  whatVerificationMeans: 'We check your documents.',
  discipline: CoachDiscipline.nutritionist,
  coachingAgreementAccepted: coachingAgreementAccepted,
);

void main() {
  late _FakeCoach coach;

  setUp(() => coach = _FakeCoach());
  tearDown(Get.reset);

  Widget tab({TextScaler scaler = TextScaler.noScaling}) {
    Get
      ..reset()
      ..put<CoachRepository>(coach, permanent: true);
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
        child: const Scaffold(body: CoachYouTab()),
      ),
    );
  }

  testWidgets('should wait behind a skeleton while it asks the server', (tester) async {
    coach.hold = Completer<void>();
    await tester.pumpWidget(tab());
    await tester.pump();

    expect(find.byType(Skeleton), findsOneWidget);

    coach.hold!.complete();
    await settle(tester);
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets('should say "not a partner yet" rather than showing nothing', (tester) async {
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.text('Not a partner yet'), findsOneWidget);
    expect(find.text('My partner profile'), findsOneWidget);
  });

  testWidgets('should render a failure with a retry', (tester) async {
    coach.result = const Left(OfflineFailure('You are offline.'));
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.byType(FailedView), findsOneWidget);
    expect(find.text('You are offline.'), findsOneWidget);
  });

  testWidgets('should show a submitted application as in progress, never as verified', (
    tester,
  ) async {
    coach.result = Right(applicationWith());
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.text('Verification in progress'), findsOneWidget);
    expect(find.text('Verified partner'), findsNothing);
    expect(find.text('Level 1'), findsOneWidget);
  });

  testWidgets('should say verified once an admin has decided it', (tester) async {
    coach.result = Right(applicationWith(status: 'verified', level: 2));
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.text('Verified partner'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
  });

  /// D-174: a coach is a client of their own app, so leaving the coach surface is a way back, not
  /// a second copy of the client screens.
  testWidgets('should offer the way back to their own account', (tester) async {
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.text('Back to my own account'), findsOneWidget);
    expect(find.textContaining('client of Eatzify too'), findsOneWidget);
  });

  testWidgets('should survive a 200 % text scale', (tester) async {
    coach.result = Right(applicationWith());
    await tester.pumpWidget(tab(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  /// docs/12 §6's level 3 — the only one that may ask a client for chat (D-235).
  group('becoming a Coaching Partner', () {
    testWidgets('should offer nothing before verification', (tester) async {
      coach.result = Right(applicationWith());
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.text('Coaching agreement'), findsNothing);
    });

    testWidgets('should offer the coaching agreement to a verified partner', (tester) async {
      coach
        ..result = Right(applicationWith(status: 'verified', level: 2))
        ..afterCoaching = applicationWith(
          status: 'verified',
          level: 2,
          coachingAgreementAccepted: true,
        );
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.text('Coaching agreement'), findsOneWidget);

      await tester.tap(find.text('Accept the coaching agreement'));
      await settle(tester);

      expect(coach.coachingVersions, ['c1']);
      // Two of three conditions: still level 2 until a client says yes, and the card says so.
      expect(find.text('Almost a Coaching Partner'), findsOneWidget);
    });

    testWidgets('should say what a Coaching Partner can now do', (tester) async {
      coach.result = Right(
        applicationWith(status: 'verified', level: 3, coachingAgreementAccepted: true),
      );
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.text('Coaching Partner'), findsOneWidget);
      expect(find.text('Accept the coaching agreement'), findsNothing);
    });
  });
}
