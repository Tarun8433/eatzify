import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/local/gym_local_data_source.dart';
import 'package:health_pro/data/datasources/remote/gym_remote_data_source.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/gym_stats.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';

class GymRepositoryImpl implements GymRepository {
  const GymRepositoryImpl(this._remote, this._local);

  final GymRemoteDataSource _remote;
  final GymLocalDataSource _local;

  @override
  Future<Either<Failure, GymOverview>> overview() async {
    final result = await _remote.overview();
    return result.fold((failure) async {
      final cached = await _cached(GymLocalDataSource.overviewKey, failure);
      return cached.map((json) => GymOverview.fromJson(json, fromCache: true));
    }, (json) => _remember(GymLocalDataSource.overviewKey, json, GymOverview.fromJson));
  }

  @override
  Future<Either<Failure, List<Exercise>>> exercises() async {
    List<Exercise> parse(Json json) => (json['exercises'] as List? ?? [])
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
    final result = await _remote.exercises();
    return result.fold(
      (failure) async => (await _cached(GymLocalDataSource.exercisesKey, failure)).map(parse),
      (json) => _remember(GymLocalDataSource.exercisesKey, json, parse),
    );
  }

  @override
  Future<Either<Failure, ExerciseDetail>> exercise(String id) async =>
      (await _remote.exercise(id)).map(ExerciseDetail.fromJson);

  @override
  Future<Either<Failure, ExerciseProgress>> progress(String id) async =>
      (await _remote.progress(id)).map(ExerciseProgress.fromJson);

  @override
  Future<Either<Failure, Exercise>> createExercise({
    required String name,
    required String bodyPart,
    String? description,
  }) async => (await _remote.createExercise({
    'name': name,
    'body_part': bodyPart,
    'description': ?description,
  })).map(Exercise.fromJson);

  @override
  Future<Either<Failure, Exercise>> updateExercise(
    String id, {
    required String name,
    required String bodyPart,
    String? description,
  }) async => (await _remote.updateExercise(id, {
    'name': name,
    'body_part': bodyPart,
    'description': description,
  })).map(Exercise.fromJson);

  @override
  Future<Either<Failure, Unit>> deleteExercise(String id) => _remote.deleteExercise(id);

  @override
  Future<Either<Failure, Routine>> saveRoutine(RoutineDraft draft) async {
    final id = draft.id;
    final result = id == null
        ? await _remote.createRoutine(draft.toJson())
        : await _remote.updateRoutine(id, draft.toJson());
    return result.map(Routine.fromJson);
  }

  @override
  Future<Either<Failure, Unit>> deleteRoutine(int id) => _remote.deleteRoutine(id);

  @override
  Future<Either<Failure, GymOverview>> loadStarterPlan() async =>
      _overviewFrom(await _remote.starter());

  @override
  Future<Either<Failure, GymOverview>> setSchedule(Map<int, int?> week) async => _overviewFrom(
    await _remote.schedule({
      'week': {for (var day = 1; day <= DateTime.daysPerWeek; day++) '$day': week[day]},
    }),
  );

  @override
  Future<Either<Failure, GymOverview>> setDay({
    required String date,
    int? routineId,
    bool rest = false,
  }) async => _overviewFrom(
    await _remote.day({'date': date, 'routine_id': ?routineId, if (rest) 'rest': true}),
  );

  @override
  Future<Either<Failure, GymSettings>> updateSettings(GymSettings settings) async =>
      (await _remote.settings(settings.toJson())).map(GymSettings.fromJson);

  @override
  Future<Either<Failure, WorkoutDetail>> saveWorkout(WorkoutDraft draft) async {
    await _queue((pending) => [...pending.where((p) => p.id != draft.id), draft]);
    final result = await _remote.saveWorkout(draft.toWire());
    if (result.isRight() || _isFinal(result)) {
      await _queue((pending) => pending.where((p) => p.id != draft.id).toList());
    }
    return result.map(WorkoutDetail.fromJson);
  }

  @override
  Future<int> sendPending() async {
    for (final draft in await pendingWorkouts()) {
      final result = await _remote.saveWorkout(draft.toWire());
      if (result.isRight() || _isFinal(result)) {
        await _queue((pending) => pending.where((p) => p.id != draft.id).toList());
      }
    }
    return (await pendingWorkouts()).length;
  }

  @override
  Future<List<WorkoutDraft>> pendingWorkouts() async {
    final raw = await _local.read(GymLocalDataSource.pendingKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((d) => WorkoutDraft.fromJson(d as Map<String, dynamic>))
          .toList();
    } on Object {
      return const [];
    }
  }

  @override
  Future<Either<Failure, ({List<WorkoutSummary> workouts, String? nextCursor})>> history({
    String? before,
  }) async => (await _remote.history(before: before)).map(
    (json) => (
      workouts: WorkoutSummary.listFrom(json['workouts']),
      nextCursor: json['next_cursor'] as String?,
    ),
  );

  @override
  Future<Either<Failure, WorkoutDetail>> workout(String id) async =>
      (await _remote.workout(id)).map(WorkoutDetail.fromJson);

  @override
  Future<Either<Failure, Unit>> deleteWorkout(String id) => _remote.deleteWorkout(id);

  @override
  Future<Either<Failure, GymStats>> stats({
    String? muscleWindow,
    String? effortWindow,
    bool? hard,
  }) async => (await _remote.stats(
    muscleWindow: muscleWindow,
    effortWindow: effortWindow,
    hard: hard,
  )).map(GymStats.fromJson);

  @override
  Future<Either<Failure, GymCalendar>> calendar(String month) async =>
      (await _remote.calendar(month)).map(GymCalendar.fromJson);

  @override
  Future<WorkoutSession?> activeWorkout() async {
    final raw = await _local.read(GymLocalDataSource.activeKey);
    if (raw == null) return null;
    try {
      return WorkoutSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveActiveWorkout(WorkoutSession? session) => _local.write(
    GymLocalDataSource.activeKey,
    session == null ? null : jsonEncode(session.toJson()),
  );

  @override
  Future<void> clearLocal() => _local.clear();

  Future<Either<Failure, GymOverview>> _overviewFrom(Either<Failure, Json> result) => result.fold(
    (failure) async => Left(failure),
    (json) => _remember(GymLocalDataSource.overviewKey, json, GymOverview.fromJson),
  );

  Future<Either<Failure, T>> _remember<T>(String key, Json json, T Function(Json) parse) async {
    await _local.write(key, jsonEncode(json));
    return Right(parse(json));
  }

  /// The last copy, but only when the failure was the connection — a server that answered "no"
  /// is not overruled by a stale copy.
  Future<Either<Failure, Json>> _cached(String key, Failure failure) async {
    if (failure is! OfflineFailure) return Left(failure);
    final raw = await _local.read(key);
    if (raw == null) return Left(failure);
    return Right(jsonDecode(raw) as Json);
  }

  /// A refusal the server will give again (a 4xx other than auth or rate limit) takes the workout
  /// out of the queue; retrying it forever would block every workout behind it.
  bool _isFinal(Either<Failure, Object?> result) => result.fold((failure) {
    if (failure is! ApiFailure) return false;
    final status = failure.status ?? 0;
    return status >= 400 && status < 500 && status != 401 && status != 408 && status != 429;
  }, (_) => false);

  Future<void> _queue(List<WorkoutDraft> Function(List<WorkoutDraft>) change) async {
    final next = change(await pendingWorkouts());
    await _local.write(
      GymLocalDataSource.pendingKey,
      next.isEmpty ? null : jsonEncode([for (final d in next) d.toJson()]),
    );
  }
}
