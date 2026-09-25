import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/gym_stats.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';
import 'package:health_pro/presentation/features/gym/workout_feedback.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Stands in for `/gym` so the Gym screens can be driven without a dio.
class FakeGymRepository implements GymRepository {
  FakeGymRepository({this.overviewResult, this.exercisesResult, this.statsResult, this.saveResult});

  Either<Failure, GymOverview>? overviewResult;
  Either<Failure, List<Exercise>>? exercisesResult;
  Either<Failure, GymStats>? statsResult;
  Either<Failure, WorkoutDetail>? saveResult;

  /// When set, the overview is not answered until this completes — the Loading state, held.
  Completer<void>? overviewGate;

  int overviewCalls = 0;
  int starterCalls = 0;
  WorkoutSession? active;
  final saved = <WorkoutDraft>[];
  final pending = <WorkoutDraft>[];

  @override
  Future<Either<Failure, GymOverview>> overview() async {
    overviewCalls++;
    await overviewGate?.future;
    return overviewResult ?? Right(sampleOverview());
  }

  @override
  Future<Either<Failure, List<Exercise>>> exercises() async =>
      exercisesResult ?? const Right(sampleExercises);

  @override
  Future<Either<Failure, ExerciseDetail>> exercise(String id) async =>
      const Left(OfflineFailure('offline'));

  @override
  Future<Either<Failure, ExerciseProgress>> progress(String id) async =>
      const Left(OfflineFailure('offline'));

  @override
  Future<Either<Failure, Exercise>> createExercise({
    required String name,
    required String bodyPart,
    String? description,
  }) async => Right(
    Exercise(
      id: 'c-1',
      name: name,
      bodyPart: bodyPart,
      equipment: 'custom',
      target: '',
      isCustom: true,
    ),
  );

  @override
  Future<Either<Failure, Exercise>> updateExercise(
    String id, {
    required String name,
    required String bodyPart,
    String? description,
  }) async => Right(
    Exercise(
      id: id,
      name: name,
      bodyPart: bodyPart,
      equipment: 'custom',
      target: '',
      isCustom: true,
    ),
  );

  @override
  Future<Either<Failure, Unit>> deleteExercise(String id) async => const Right(unit);

  @override
  Future<Either<Failure, Routine>> saveRoutine(RoutineDraft draft) async => Right(
    Routine(
      id: draft.id ?? 99,
      name: draft.name,
      icon: draft.icon,
      progression: draft.progression,
      items: const [],
    ),
  );

  @override
  Future<Either<Failure, Unit>> deleteRoutine(int id) async => const Right(unit);

  @override
  Future<Either<Failure, GymOverview>> loadStarterPlan() async {
    starterCalls++;
    return Right(sampleOverview());
  }

  @override
  Future<Either<Failure, GymOverview>> setSchedule(Map<int, int?> week) async =>
      Right(sampleOverview());

  @override
  Future<Either<Failure, GymOverview>> setDay({
    required String date,
    int? routineId,
    bool rest = false,
  }) async => Right(sampleOverview());

  @override
  Future<Either<Failure, GymSettings>> updateSettings(GymSettings settings) async =>
      Right(settings);

  @override
  Future<Either<Failure, WorkoutDetail>> saveWorkout(WorkoutDraft draft) async {
    saved.add(draft);
    return saveResult ??
        Right(
          WorkoutDetail(
            summary: WorkoutSummary(
              id: draft.id,
              name: draft.name,
              diaryDate: '2026-09-21',
              startedAt: draft.startedAt,
              durationSec: 1800,
              setsDone: 3,
              volumeKg: 1440,
              energyKcal: 120,
            ),
            entries: const [],
          ),
        );
  }

  @override
  Future<int> sendPending() async => pending.length;

  @override
  Future<List<WorkoutDraft>> pendingWorkouts() async => pending;

  @override
  Future<Either<Failure, ({List<WorkoutSummary> workouts, String? nextCursor})>> history({
    String? before,
  }) async => const Right((workouts: <WorkoutSummary>[], nextCursor: null));

  @override
  Future<Either<Failure, WorkoutDetail>> workout(String id) async =>
      const Left(OfflineFailure('offline'));

  @override
  Future<Either<Failure, Unit>> deleteWorkout(String id) async => const Right(unit);

  @override
  Future<Either<Failure, GymStats>> stats({
    String? muscleWindow,
    String? effortWindow,
    bool? hard,
  }) async => statsResult ?? Right(emptyStats());

  @override
  Future<Either<Failure, GymCalendar>> calendar(String month) async =>
      const Left(OfflineFailure('offline'));

  @override
  Future<WorkoutSession?> activeWorkout() async => active;

  @override
  Future<void> saveActiveWorkout(WorkoutSession? session) async => active = session;

  @override
  Future<void> clearLocal() async => active = null;
}

class SilentFeedback implements WorkoutFeedback {
  int checks = 0;
  bool? awake;

  @override
  Future<void> setChecked({required bool sound}) async => checks++;
  @override
  Future<void> restEnding({required bool sound}) async {}
  @override
  Future<void> restOver({required bool sound}) async {}
  @override
  Future<void> workoutSaved({required bool sound}) async {}
  @override
  Future<void> keepAwake({required bool on}) async => awake = on;
  @override
  Future<void> scheduleRestAlert(
    DateTime at, {
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> cancelRestAlert() async {}
}

const sampleExercises = [
  Exercise(
    id: '0025',
    name: 'barbell bench press',
    bodyPart: 'chest',
    equipment: 'barbell',
    target: 'pectorals',
  ),
  Exercise(
    id: '0662',
    name: 'push-up',
    bodyPart: 'chest',
    equipment: 'body weight',
    target: 'pectorals',
    isBodyweight: true,
  ),
  Exercise(
    id: '0043',
    name: 'barbell full squat',
    bodyPart: 'upper legs',
    equipment: 'barbell',
    target: 'glutes',
  ),
  Exercise(
    id: '0685',
    name: 'run',
    bodyPart: 'cardio',
    equipment: 'body weight',
    target: 'cardiovascular system',
    isCardio: true,
  ),
];

SessionEntry benchEntry({int sets = 2}) => SessionEntry(
  exerciseId: '0025',
  name: 'barbell bench press',
  mode: ExerciseMode.reps,
  bodyPart: 'chest',
  target: RoutineExercise(
    exerciseId: '0025',
    mode: ExerciseMode.reps,
    sets: sets,
    reps: 8,
    weightKg: 60,
  ),
  sets: List.generate(sets, (_) => const WorkoutSet(weightKg: 60, reps: 8)),
  prescription: const Prescription(
    rule: ProgressionRule.linear,
    kind: 'up',
    whyCode: 'up_weight',
    whyArgs: {'step': 2.5},
  ),
  bestWeightKg: 57.5,
);

GymOverview sampleOverview({
  bool withPlan = true,
  bool restToday = false,
  GymTotals totals = const GymTotals(
    todayKcal: 240,
    weekKcal: 610,
    streakWeeks: 2,
    thisWeekWorkouts: 1,
    plannedPerWeek: 3,
    totalWorkouts: 9,
  ),
}) {
  const push = Routine(
    id: 1,
    name: 'Push Day',
    icon: RoutineIcon.strength,
    progression: ProgressionRule.linear,
    items: [
      RoutineItem(
        config: RoutineExercise(
          exerciseId: '0025',
          mode: ExerciseMode.reps,
          sets: 3,
          reps: 8,
          weightKg: 60,
        ),
        name: 'barbell bench press',
        bodyPart: 'chest',
        equipment: 'barbell',
        isBodyweight: false,
        isCardio: false,
      ),
    ],
  );
  final days = [
    for (var i = 0; i < 7; i++)
      PlannedDay(
        diaryDate: '2026-09-${(21 + i).toString().padLeft(2, '0')}',
        weekday: i + 1,
        source: i == 0 && restToday
            ? DaySource.restOverride
            : withPlan && i == 0
            ? DaySource.weekly
            : DaySource.none,
        routineId: withPlan && i == 0 && !restToday ? 1 : null,
        isToday: i == 0,
      ),
  ];
  return GymOverview(
    settings: const GymSettings(),
    week: withPlan ? const {1: 1} : const {},
    routines: withPlan ? const [push] : const [],
    today: days.first,
    weekDays: days,
    sessionPlans: withPlan
        ? {
            1: [benchEntry()],
          }
        : const {},
    totals: totals,
    recent: const [],
  );
}

GymStats emptyStats({int total = 0}) => GymStats(
  totalWorkouts: total,
  thisMonth: total,
  streakWeeks: 0,
  heatmap: const [],
  muscles: const MuscleBalance(
    window: 'week',
    hard: false,
    hasHardSets: false,
    workouts: 0,
    levels: [],
    untrained: [],
    top: [],
  ),
  energyDays: const [],
  recent: const [],
  exercises: const [],
);

Widget gymApp(Widget home, {TextScaler scaler = TextScaler.noScaling, bool dark = false}) =>
    GetMaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: home,
      ),
    );
