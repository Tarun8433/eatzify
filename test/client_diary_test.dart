import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/macro_tile.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/client_diary_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// D-206. What the client actually ate, for the coach they shared it with.
///
/// The screen answers a nutritionist's first question — what, when, and against what target. What
/// is tested is that it never fills a gap in: an unlogged day is unlogged, and an unmeasured step
/// count is not zero steps.

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.day, this.failure});

  final DiaryDay? day;
  final Failure? failure;

  /// Which dates the screen asked for, in order. The first must be null — the server owns the
  /// diary boundary (rule 8) and the app must not guess today's date.
  final List<String?> asked = [];

  @override
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) async {
    asked.add(date);
    final f = failure;
    return f != null ? Left(f) : Right(day!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

DiaryDay dayWith({List<LogEntry> entries = const [], Macros? targets, int? steps, int? burned}) =>
    DiaryDay(
      diaryDate: '2026-09-15',
      entries: entries,
      totals: const Macros(kcal: 1740, proteinG: 96, carbG: 210, fatG: 52),
      targets: targets,
      steps: steps,
      stepsSource: MeasurementSource.manual,
      energyBurnedKcal: burned,
    );

LogEntry entry({
  String slot = 'lunch',
  String name = 'Dal tadka',
  String? measure = '1.5 katori',
  double kcal = 240,
}) => LogEntry(
  id: '$slot-$name',
  slot: slot,
  name: name,
  quantityG: 150,
  measureLabel: measure,
  kcal: kcal,
  proteinG: 9,
  carbG: 28,
  fatG: 7,
  locked: false,
);

Widget pageWith(FakeCoachRepository repo) {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ClientDiaryPage(clientUserId: 6, name: 'Ritu Agarwal'),
  );
}

void main() {
  /// Rule 8. The 04:00 IST diary boundary is the server's, so the first read sends no date at all
  /// rather than the device's idea of today.
  testWidgets('should ask the server which day today is', (tester) async {
    final repo = FakeCoachRepository(day: dayWith(entries: [entry()]));
    await tester.pumpWidget(pageWith(repo));
    await settle(tester);

    expect(repo.asked, [null]);
  });

  testWidgets('should show what they ate, and in what measure', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(day: dayWith(entries: [entry()]))));
    await settle(tester);

    // The measure the client chose, not the grams a database stored.
    expect(find.textContaining('Dal tadka'), findsOneWidget);
    expect(find.textContaining('1.5 katori'), findsOneWidget);
  });

  /// A coach reads a diary the way it was eaten. Rows arriving in any order still render
  /// breakfast before dinner.
  testWidgets('should read in the order the day happened', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          day: dayWith(
            entries: [
              entry(slot: 'dinner', name: 'Roti sabzi'),
              entry(slot: 'breakfast', name: 'Poha'),
            ],
          ),
        ),
      ),
    );
    await settle(tester);

    final breakfast = tester.getTopLeft(find.text('Breakfast')).dy;
    final dinner = tester.getTopLeft(find.text('Dinner')).dy;
    expect(breakfast, lessThan(dinner));
  });

  /// A number alone tells a coach nothing they can act on. 1,740 kcal means something only beside
  /// the 1,859 the plan asked for.
  testWidgets('should print each total beside its target', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          day: dayWith(
            entries: [entry()],
            targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
          ),
        ),
      ),
    );
    await settle(tester);

    // The gauge carries the calories and the bars carry the macros, the same widgets the client
    // sees on their own Home tab.
    expect(find.byType(MacroTile), findsNWidgets(3));
    expect(find.text('1740'), findsOneWidget);
    expect(find.textContaining('1859'), findsWidgets);
    expect(find.textContaining('125'), findsWidgets);
  });

  /// docs/04 §2: a plan with no targets fired a blocking gate. The screen says so rather than
  /// comparing against zero.
  testWidgets('should say there is nothing to compare against with no plan', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(day: dayWith(entries: [entry()]))));
    await settle(tester);

    // The figure stands alone; there is no target beside it to compare against.
    expect(find.text('1740'), findsOneWidget);
    expect(find.textContaining('1859'), findsNothing);
  });

  /// D-80's rule, on the coach's side of the glass. "They burned nothing" and "nobody measured"
  /// are different sentences and only one of them is ever true.
  testWidgets('should say not recorded rather than zero for steps', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(day: dayWith(entries: [entry()]))));
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('Moved'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Not recorded'), findsWidgets);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('should show the figures once they were recorded', (tester) async {
    await tester.pumpWidget(
      pageWith(FakeCoachRepository(day: dayWith(entries: [entry()], steps: 8200, burned: 410))),
    );
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('Moved'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('8200'), findsOneWidget);
    expect(find.text('410 kcal'), findsOneWidget);
  });

  /// An unlogged day is an answer, and a useful one. Not a failure and not a broken screen.
  testWidgets('should say plainly when nothing was logged', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(day: dayWith())));
    await settle(tester);

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('Nothing logged on this day.'), findsOneWidget);
  });

  /// The server answers "no grant" and "no such person" the same way. For a coach that is access
  /// ending, not an error worth a retry button.
  testWidgets('should treat a refused diary as nothing to show', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          failure: const ApiFailure('no access', code: 'CLIENT_NOT_FOUND', status: 404),
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.byType(FailedView), findsNothing);
  });

  /// Rule 7: a real failure still shows the server's words and a retry.
  testWidgets('should show the server message when the read fails', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          failure: const ApiFailure('Could not load the diary.', code: 'X', status: 500),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Could not load the diary.'), findsOneWidget);
  });

  /// Stepping back asks for a date derived from what the SERVER last said, never from the device
  /// clock — the same reason the first read sends nothing.
  testWidgets('should step back from the date the server returned', (tester) async {
    final repo = FakeCoachRepository(day: dayWith(entries: [entry()]));
    await tester.pumpWidget(pageWith(repo));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await settle(tester);

    expect(repo.asked, [null, '2026-09-14']);
  });

  /// The bug this closed: the footer said "no plan for this day" under a screen full of targets.
  /// A screen telling a coach two different things at once is worse than one telling them less.
  testWidgets('should not claim there is no plan while showing targets', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          day: dayWith(
            entries: [entry()],
            targets: const Macros(kcal: 1859, proteinG: 125, carbG: 223, fatG: 52),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.textContaining('nothing to compare against'), findsNothing);
  });

  testWidgets('should say there is no plan when there is not', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(day: dayWith(entries: [entry()]))));
    await settle(tester);

    await tester.scrollUntilVisible(
      find.textContaining('nothing to compare against'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('nothing to compare against'), findsOneWidget);
  });
}
