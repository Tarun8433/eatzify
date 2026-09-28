import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/local/gym_local_data_source.dart';
import 'package:health_pro/data/datasources/remote/gym_remote_data_source.dart';
import 'package:health_pro/data/repositories/gym_repository_impl.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';

/// Answers each path with a canned status and body; `offline` makes every call a connection error.
class _Server implements HttpClientAdapter {
  final routes = <String, (int, Object)>{};
  final requests = <RequestOptions>[];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    requests.add(o);
    if (offline) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
    final (status, body) =
        routes['${o.method} ${o.path}'] ??
        (
          404,
          {
            'error': {'code': 'X', 'user_message': 'no'},
          },
        );
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryStore implements GymLocalDataSource {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

const _overview = {
  'settings': {
    'rest_sec': 120,
    'effort_scale': 'rir',
    'keep_awake': true,
    'sound': false,
    'body_figure': 'female',
  },
  'week': {'1': 7},
  'routines': [
    {
      'id': 7,
      'name': 'Push Day',
      'icon': 'strength',
      'progression': 'double',
      'exercises': [
        {
          'exercise_id': '0025',
          'mode': 'reps',
          'sets': 3,
          'reps': 8,
          'name': 'barbell bench press',
          'body_part': 'chest',
          'equipment': 'barbell',
          'is_bodyweight': false,
          'is_cardio': false,
        },
      ],
    },
  ],
  'today': {
    'diary_date': '2026-09-21',
    'weekday': 1,
    'routine_id': 7,
    'source': 'weekly',
    'workouts': 0,
    'is_today': true,
  },
  'week_days': <Object>[],
  'session_plans': {
    '7': [
      {
        'exercise_id': '0025',
        'name': 'barbell bench press',
        'mode': 'reps',
        'body_part': 'chest',
        'target': {'exercise_id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 8, 'weight_kg': 62.5},
        'sets': [
          {'weight_kg': 62.5, 'reps': 8, 'done': false},
        ],
        'prescription': {
          'rule': 'linear',
          'kind': 'up',
          'why': {'code': 'up_weight', 'step': 2.5},
        },
        'last': {'date': '2026-09-14', 'sets': <Object>[]},
        'best_weight_kg': 60,
      },
    ],
  },
  'totals': {
    'today_kcal': null,
    'week_kcal': 240,
    'streak_weeks': 2,
    'this_week_workouts': 1,
    'planned_per_week': 1,
    'total_workouts': 5,
  },
  'recent': <Object>[],
};

WorkoutDraft _draft(String id) => WorkoutDraft(
  id: id,
  name: 'Push Day',
  startedAt: DateTime.utc(2026, 9, 21, 7),
  endedAt: DateTime.utc(2026, 9, 21, 8),
  entries: [
    const SessionEntry(
      exerciseId: '0025',
      name: 'barbell bench press',
      mode: ExerciseMode.reps,
      bodyPart: 'chest',
      target: RoutineExercise(exerciseId: '0025', mode: ExerciseMode.reps, sets: 1, reps: 8),
      sets: [WorkoutSet(weightKg: 60, reps: 8, done: true)],
    ),
  ],
);

void main() {
  late _Server server;
  late _MemoryStore store;
  late GymRepositoryImpl repo;

  setUp(() {
    server = _Server();
    store = _MemoryStore();
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = server;
    repo = GymRepositoryImpl(GymRemoteDataSource(dio), store);
  });

  group('overview', () {
    test('parses the hub and keeps a copy for no signal', () async {
      server.routes['GET /gym'] = (200, _overview);
      final overview = (await repo.overview()).getOrElse(() => throw StateError('left'));

      expect(overview.settings.restSec, 120);
      expect(overview.settings.bodyFigure, BodyFigure.female);
      expect(overview.routines.single.progression, ProgressionRule.doubleProgression);
      expect(overview.todaysRoutine?.name, 'Push Day');
      expect(overview.sessionPlans[7]!.single.prescription!.whyCode, 'up_weight');
      expect(overview.sessionPlans[7]!.single.prescription!.arg('step'), 2.5);
      expect(overview.totals.todayKcal, isNull);
      expect(overview.fromCache, isFalse);
      expect(store.values, contains(GymLocalDataSource.overviewKey));
    });

    test('falls back to the last copy with no signal, and says so', () async {
      server.routes['GET /gym'] = (200, _overview);
      await repo.overview();
      server.offline = true;

      final overview = (await repo.overview()).getOrElse(() => throw StateError('left'));
      expect(overview.fromCache, isTrue);
      expect(overview.sessionPlans[7], hasLength(1));
    });

    test('does not hide a server refusal behind a stale copy', () async {
      server.routes['GET /gym'] = (200, _overview);
      await repo.overview();
      server.routes['GET /gym'] = (
        500,
        {
          'error': {'code': 'BOOM', 'user_message': 'Try again later.'},
        },
      );

      final result = await repo.overview();
      expect(result.fold((f) => f.userMessage, (_) => ''), 'Try again later.');
    });

    test('is an offline failure with no signal and nothing saved', () async {
      server.offline = true;
      expect((await repo.overview()).fold((f) => f, (_) => null), isA<OfflineFailure>());
    });
  });

  group('saving a workout', () {
    test('sends it and leaves nothing queued', () async {
      server.routes['POST /gym/workouts'] = (
        200,
        {
          'id': 'w1',
          'name': 'Push Day',
          'energy_kcal': 210,
          'entries': <Object>[],
          'prs': <Object>[],
        },
      );
      final saved = (await repo.saveWorkout(
        _draft('w1'),
      )).getOrElse(() => throw StateError('left'));

      expect(saved.summary.energyKcal, 210);
      expect(await repo.pendingWorkouts(), isEmpty);
      final body = server.requests.single.data as Map<String, dynamic>;
      expect(body['id'], 'w1');
      expect(body['started_at'], '2026-09-21T07:00:00.000Z');
      expect((body['entries'] as List).single, containsPair('exercise_id', '0025'));
    });

    test('keeps it on the phone with no signal and sends it later', () async {
      server.offline = true;
      expect((await repo.saveWorkout(_draft('w2'))).isLeft(), isTrue);
      expect((await repo.pendingWorkouts()).single.id, 'w2');

      server
        ..offline = false
        ..routes['POST /gym/workouts'] = (
          200,
          {'id': 'w2', 'entries': <Object>[], 'prs': <Object>[]},
        );
      expect(await repo.sendPending(), 0);
    });

    test('drops a workout the server refuses for good, so it cannot block the queue', () async {
      server.routes['POST /gym/workouts'] = (
        422,
        {
          'error': {'code': 'GYM_INVALID', 'user_message': 'no'},
        },
      );
      await repo.saveWorkout(_draft('w3'));
      expect(await repo.pendingWorkouts(), isEmpty);
    });
  });

  test('the workout in progress survives a restart, and clears', () async {
    final session = WorkoutSession.start(
      name: 'Freestyle',
      plan: const [],
      now: DateTime.utc(2026),
      id: 's1',
    );
    await repo.saveActiveWorkout(session);
    expect((await repo.activeWorkout())?.id, 's1');
    await repo.saveActiveWorkout(null);
    expect(await repo.activeWorkout(), isNull);
  });

  test('a schedule is sent as all seven days, rest as null', () async {
    server.routes['PUT /gym/schedule'] = (200, _overview);
    await repo.setSchedule({1: 7, 3: 8});
    final week = (server.requests.single.data as Map<String, dynamic>)['week'] as Map;
    expect(week, {'1': 7, '2': null, '3': 8, '4': null, '5': null, '6': null, '7': null});
  });
}
