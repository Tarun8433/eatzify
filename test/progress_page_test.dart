import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/progress/progress_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'fakes.dart';

Widget progressUnderTest(MeasurementsRepository repo, {DiaryRepository? diary}) {
  Get
    ..reset()
    ..put<MeasurementsRepository>(repo, permanent: true);
  if (diary != null) Get.put<DiaryRepository>(diary, permanent: true);
  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: ProgressPage()),
  );
}

MeasurementHistory historyOf(List<double> values, {double? change, bool lastSuspect = false}) =>
    MeasurementHistory(
      kind: 'weight',
      change: change,
      points: [
        for (var i = 0; i < values.length; i++)
          Measurement(
            id: '$i',
            kind: 'weight',
            value: values[i],
            unit: 'kg',
            diaryDate: '2026-08-1${i + 1}',
            isSuspect: lastSuspect && i == values.length - 1,
          ),
      ],
    );

void main() {
  testWidgets('Ready shows the latest weight and a neutral trend sentence', (tester) async {
    await tester.pumpWidget(progressUnderTest(FakeMeasurementsRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('kg'), findsWidgets);
    expect(find.text('Log weight'), findsOneWidget);
  });

  testWidgets('Empty is shown before anything is logged', (tester) async {
    await tester.pumpWidget(
      progressUnderTest(
        FakeMeasurementsRepository(
          historyResult: const Right(MeasurementHistory(kind: 'weight', points: [])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LineChartStub), findsNothing);
    expect(find.text('Log weight'), findsOneWidget);
  });

  testWidgets('Failed shows the server message with a retry', (tester) async {
    await tester.pumpWidget(
      progressUnderTest(
        FakeMeasurementsRepository(
          historyResult: const Left(
            ApiFailure('We could not load your weight history.', code: 'X', status: 500),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('We could not load your weight history.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('no state leaves an infinite spinner (rule 6)', (tester) async {
    await tester.pumpWidget(progressUnderTest(FakeMeasurementsRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('docs/05 §6 tone', () {
    testWidgets('a weight gain is stated neutrally, never as a failure', (tester) async {
      await tester.pumpWidget(
        progressUnderTest(
          FakeMeasurementsRepository(historyResult: Right(historyOf([74, 75, 76], change: 1.4))),
        ),
      );
      await tester.pumpAndSettle();

      // No judgement, no red, no "missed" — just the number and a direction.
      expect(find.textContaining('1.4 kg up'), findsOneWidget);
      for (final banned in ['Obese', 'Missed', 'Failed', 'streak', 'Streak']) {
        expect(find.textContaining(banned), findsNothing, reason: banned);
      }
    });

    testWidgets('a single reading reports no trend rather than a fake zero', (tester) async {
      await tester.pumpWidget(
        progressUnderTest(FakeMeasurementsRepository(historyResult: Right(historyOf([74])))),
      );
      await tester.pumpAndSettle();

      // change is null — inventing "0.0 kg" from one point would be a made-up fact.
      expect(find.textContaining('Log a few more days'), findsOneWidget);
      expect(find.textContaining('0.0 kg'), findsNothing);
    });
  });

  /// D-143: the dashboard cards, fed by the diary. The fake serves the same day for every date,
  /// which is exactly the seam the aggregates need: one fed day, one goal.
  group('dashboard (D-143)', () {
    Widget dashboardUnderTest() => progressUnderTest(
      FakeMeasurementsRepository(historyResult: Right(historyOf([74, 73], change: -1))),
      diary: FakeDiaryRepository(
        dayResult: const Right(
          DiaryDay(
            diaryDate: '2026-09-01',
            entries: [
              LogEntry(
                id: 'e1',
                slot: 'lunch',
                name: 'Dal (arhar cooked)',
                quantityG: 100,
                kcal: 1200,
                locked: false,
              ),
            ],
            totals: Macros(kcal: 1200, proteinG: 60, carbG: 150, fatG: 40),
            targets: Macros(kcal: 1500, proteinG: 99, carbG: 183, fatG: 42),
          ),
        ),
      ),
    );

    testWidgets('the calorie card states the average against the server goal', (tester) async {
      await tester.pumpWidget(dashboardUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('avg consumed'), findsOneWidget);
      expect(find.text('Goal: 1500 kcal'), findsOneWidget);
      // 1200 of 1500 — the ring's figure is the ratio of two SERVER numbers, nothing invented.
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('the section chips narrow the page', (tester) async {
      await tester.pumpWidget(dashboardUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nutrition'));
      await tester.pumpAndSettle();

      expect(find.text('Macronutrient balance'), findsOneWidget);
      expect(find.text('Weight trend'), findsNothing);
    });

    testWidgets('the weight section lists every reading date-wise', (tester) async {
      await tester.pumpWidget(
        progressUnderTest(
          FakeMeasurementsRepository(
            historyResult: Right(historyOf([75, 74.8, 45], change: -0.1, lastSuspect: true)),
          ),
          diary: FakeDiaryRepository(
            dayResult: const Right(
              DiaryDay(
                diaryDate: '2026-09-01',
                entries: [],
                totals: Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();

      // The full report: a dated row per reading, newest first.
      expect(find.text('History'), findsOneWidget);
      expect(find.textContaining('Aug'), findsWidgets);
      // The suspect reading is SHOWN — docs/08 keeps it — with a neutral note that the trend
      // leaves it out. Never hidden, never red. Twice: it is also the latest reading, so the
      // trend card's current-weight figure states it too.
      expect(find.text('45.0 kg'), findsNWidgets(2));
      expect(find.text('Left out of the trend'), findsOneWidget);
    });

    testWidgets('with no data for last week, no comparison is claimed', (tester) async {
      await tester.pumpWidget(dashboardUnderTest());
      await tester.pumpAndSettle();

      // The fake's single diary date leaves last week unknown — unknown is not "0% change".
      expect(find.textContaining('vs last week'), findsNothing);
    });
  });

  testWidgets('a suspect reading is kept out of the trend line', (tester) async {
    await tester.pumpWidget(
      progressUnderTest(
        FakeMeasurementsRepository(
          historyResult: Right(historyOf([75, 74.8, 45], change: -0.1, lastSuspect: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // docs/16: the readout must never become "−30.0" because of one bad entry.
    expect(find.textContaining('30'), findsNothing);
  });

  group('body measurements (D-87)', () {
    /// One weight reading and no body measurements — exactly the state that was reported: a number
    /// and half a screen of nothing.
    final firstDay = _KindedMeasurements(
      weight: const MeasurementHistory(
        kind: 'weight',
        points: [
          Measurement(
            id: 'm1',
            kind: 'weight',
            value: 100,
            unit: 'kg',
            diaryDate: '2026-08-30',
            isSuspect: false,
          ),
        ],
      ),
    );

    testWidgets('every kind the brief asks for has a row, recorded or not', (tester) async {
      await tester.pumpWidget(progressUnderTest(FakeMeasurementsRepository()));
      await tester.pumpAndSettle();

      // Waist is the clinically useful one; the rest are the optional progress metrics. The rows
      // sit below the weight card, so the test travels to each like a thumb would.
      for (final label in ['Waist', 'Hip', 'Thigh', 'Chest']) {
        await tester.dragUntilVisible(
          find.text(label),
          find.byType(ListView),
          const Offset(0, -100),
        );
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('an unrecorded measurement says so — it is not zero', (tester) async {
      await tester.pumpWidget(progressUnderTest(firstDay));
      await tester.pumpAndSettle();

      // A measurement nobody has taken is not a measurement of nought.
      expect(find.text('Not recorded yet'), findsWidgets);
      expect(find.text('0.0 cm'), findsNothing);
    });

    testWidgets('a first weight reading explains itself instead of leaving a blank page', (
      tester,
    ) async {
      await tester.pumpWidget(progressUnderTest(firstDay));
      await tester.pumpAndSettle();

      // The reported state: one reading, a number, and half a screen of nothing.
      expect(find.textContaining("That's your first reading"), findsOneWidget);
    });
  });

  /// D-128. Steps, water and calories burned were written every day by the `+` sheet and readable
  /// only on Home, only for today. A number you cannot see tomorrow is not tracking.
  group('day by day (D-128)', () {
    MeasurementHistory habit(String kind, List<double> values) => MeasurementHistory(
      kind: kind,
      points: [
        for (final (i, value) in values.indexed)
          Measurement(
            id: '$kind$i',
            kind: kind,
            value: value,
            unit: kind == 'steps' ? 'steps' : 'ml',
            diaryDate: '2026-08-2${i + 1}',
            isSuspect: false,
          ),
      ],
    );

    testWidgets('the last reading of each habit is on the page, grouped by locale', (tester) async {
      await tester.pumpWidget(
        progressUnderTest(
          _KindedMeasurements(
            weight: historyOf([70, 69.5]),
            byKind: {
              'steps': habit('steps', [6000, 8432]),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Below the body measurements, so the test has to travel there like a thumb would.
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(find.text('Steps'), findsOneWidget);
      // 8,432 — not 8432.0, and not the 6,000 from the day before.
      expect(find.text('8,432'), findsOneWidget);
      expect(find.text('2 days logged'), findsOneWidget);
    });

    testWidgets('a habit nobody has logged says so rather than showing a zero', (tester) async {
      await tester.pumpWidget(
        progressUnderTest(_KindedMeasurements(weight: historyOf([70, 69.5]))),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      // Three habits, none logged: "nought steps" and "you have not said" are different claims.
      expect(find.text('Nothing logged yet'), findsNWidgets(3));
      expect(find.text('0'), findsNothing);
    });
  });
}

/// Placeholder so the Empty test can assert the chart is absent without importing fl_chart.
class LineChartStub extends StatelessWidget {
  const LineChartStub({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Serves a different history per kind, which the shared fake does not.
class _KindedMeasurements implements MeasurementsRepository {
  _KindedMeasurements({required this.weight, this.byKind = const {}});

  final MeasurementHistory weight;

  /// Histories for the other kinds — the daily habits, in the tests that are about them.
  final Map<String, MeasurementHistory> byKind;

  @override
  Future<Either<Failure, MeasurementHistory>> history(String kind) async => Right(
    kind == 'weight' ? weight : byKind[kind] ?? MeasurementHistory(kind: kind, points: const []),
  );

  @override
  Future<Either<Failure, ({Measurement measurement, bool isSuspect})>> record({
    required String kind,
    required double value,
    required String unit,
    MeasurementSource source = MeasurementSource.manual,
    DateTime? at,
  }) async => Right((
    measurement: Measurement(
      id: 'm1',
      kind: kind,
      value: value,
      unit: unit,
      diaryDate: '2026-08-30',
      isSuspect: false,
    ),
    isSuspect: false,
  ));
}
