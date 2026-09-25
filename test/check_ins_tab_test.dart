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
import 'package:health_pro/domain/entities/check_in.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/check_ins_tab.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// docs/02 FR-5.2 and FR-5.3 on screen: the week's reviews, who needs attention, and closing one.

class _FakeCoach implements CoachRepository {
  List<CheckIn> queue = const [];
  List<CoachAlert> signals = const [];
  Failure? failure;

  /// Holds the queue open so a test can see the loading state.
  Completer<void>? hold;

  /// What the sheet sent, so a test can tell "saved" from "redrew".
  final completed = <({String id, String? notes, List<String> actions})>[];
  Failure? completeFailure;

  @override
  Future<Either<Failure, List<CheckIn>>> checkIns({String? status}) async {
    await hold?.future;
    return failure != null ? Left(failure!) : Right(queue);
  }

  @override
  Future<Either<Failure, CheckIn>> completeCheckIn({
    required String id,
    String? notes,
    List<String> actions = const [],
  }) async {
    completed.add((id: id, notes: notes, actions: actions));
    if (completeFailure != null) return Left(completeFailure!);

    final was = queue.firstWhere((c) => c.id == id);
    return Right(
      CheckIn(
        id: was.id,
        clientUserId: was.clientUserId,
        name: was.name,
        dueOn: was.dueOn,
        status: 'completed',
        completedAt: DateTime(2026, 9, 18),
        notes: notes,
        actions: actions,
        daysSinceLastLog: was.daysSinceLastLog,
      ),
    );
  }

  @override
  Future<Either<Failure, List<CoachAlert>>> alerts() async => Right(signals);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

CheckIn review({
  String id = 'c1',
  String name = 'A. Client',
  String status = 'due',
  int? daysSinceLastLog = 0,
  List<String> actions = const [],
}) => CheckIn(
  id: id,
  clientUserId: 7,
  name: name,
  dueOn: '2026-09-14',
  status: status,
  daysSinceLastLog: daysSinceLastLog,
  actions: actions,
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
        child: const Scaffold(body: CheckInsTab()),
      ),
    );
  }

  group('the four states', () {
    testWidgets('should wait behind a skeleton while the queue loads', (tester) async {
      coach.hold = Completer<void>();
      await tester.pumpWidget(tab());
      await tester.pump();

      expect(find.byType(Skeleton), findsOneWidget);

      coach.hold!.complete();
      await settle(tester);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('should say there is nothing to review yet', (tester) async {
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Nothing to review yet'), findsOneWidget);
    });

    testWidgets('should render a failure with a retry', (tester) async {
      coach.failure = const OfflineFailure('You are offline.');
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.byType(FailedView), findsOneWidget);
      expect(find.text('You are offline.'), findsOneWidget);
    });

    testWidgets('should list who is to be reviewed, and how they are logging', (tester) async {
      coach.queue = [review(daysSinceLastLog: 4)];
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.text('A. Client'), findsOneWidget);
      expect(find.text('No logs for 4 days'), findsOneWidget);
      expect(find.text('To review'), findsOneWidget);
    });
  });

  testWidgets('should mark a review that was never done (docs/02 FR-5.2)', (tester) async {
    coach.queue = [review(status: 'missed')];
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.text('Missed'), findsOneWidget);
  });

  testWidgets('should put a completed review under its own heading, with what was agreed', (
    tester,
  ) async {
    coach.queue = [
      review(status: 'completed', actions: const ['Walk after dinner']),
    ];
    await tester.pumpWidget(tab());
    await settle(tester);

    expect(find.text('Reviewed'), findsOneWidget);
    expect(find.text('Walk after dinner'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Review'), findsNothing);
  });

  group('alerts (docs/02 FR-5.3)', () {
    testWidgets('should say what is wrong in words, never a wire value', (tester) async {
      coach
        ..queue = [review()]
        ..signals = [
          const CoachAlert(
            clientUserId: 7,
            name: 'A. Client',
            kinds: ['no_logs', 'plan_expiring'],
            daysSinceLastLog: 5,
            planEndsInDays: 12,
          ),
        ];
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Has not logged for 5 days'), findsOneWidget);
      expect(find.text('Plan ends in 12 days'), findsOneWidget);
      expect(find.textContaining('no_logs'), findsNothing);
    });

    testWidgets('should stay away entirely when nobody needs chasing', (tester) async {
      coach.queue = [review()];
      await tester.pumpWidget(tab());
      await settle(tester);

      expect(find.text('Needs attention'), findsNothing);
    });
  });

  group('closing a review (docs/09 §6)', () {
    testWidgets('should send the note and the actions, then show it as reviewed', (tester) async {
      coach.queue = [review()];
      await tester.pumpWidget(tab());
      await settle(tester);

      await tester.tap(find.text('Review'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Sleeping badly');
      await tester.enterText(find.byType(TextField).last, 'Walk after dinner');
      await tester.tap(find.text('Add'));
      await settle(tester);
      await tester.tap(find.text('Save review'));
      await settle(tester);

      expect(coach.completed, hasLength(1));
      expect(coach.completed.first.notes, 'Sleeping badly');
      expect(coach.completed.first.actions, ['Walk after dinner']);
      expect(find.text('Reviewed'), findsOneWidget);
      expect(find.text('Review saved.'), findsOneWidget);
    });

    testWidgets('should say why the server refused, in its own words (rule 7)', (tester) async {
      coach
        ..queue = [review()]
        ..completeFailure = const ApiFailure(
          'Please shorten the note before saving it.',
          code: 'CHECK_IN_TOO_LONG',
        );
      await tester.pumpWidget(tab());
      await settle(tester);

      await tester.tap(find.text('Review'));
      await settle(tester);
      await tester.tap(find.text('Save review'));
      await settle(tester);

      expect(find.text('Please shorten the note before saving it.'), findsOneWidget);
      expect(find.text('To review'), findsOneWidget, reason: 'it is still open');
    });
  });

  testWidgets('should survive a 200 % text scale', (tester) async {
    coach
      ..queue = [review(daysSinceLastLog: 4)]
      ..signals = [
        const CoachAlert(
          clientUserId: 7,
          name: 'A. Client',
          kinds: ['no_logs'],
          daysSinceLastLog: 5,
        ),
      ];
    await tester.pumpWidget(tab(scaler: const TextScaler.linear(2)));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
