import 'package:dartz/dartz.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/gym/exercise.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/routine.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';

/// The Gym section's shared state (ADR-013): the hub, the library, and whatever workout is in
/// progress. One instance, used by the Gym screen and by Home's "Today's workout" card, so both
/// always say the same thing. Dropped at sign-out with the rest of one person's data.
class GymController extends GetxController {
  GymController({required this.gym, this.reminders});

  final GymRepository gym;

  /// Re-plans the phone's reminders with the week's workouts (ADR-013). Null in tests.
  final RefreshReminders? reminders;

  final overview = Rx<ViewState<GymOverview>>(const Loading());
  final exercises = Rx<ViewState<List<Exercise>>>(const Loading());

  /// The workout in progress, restored from the phone after a restart.
  final active = Rxn<WorkoutSession>();

  /// Workouts saved on the phone that the server has not taken yet.
  final pending = 0.obs;

  /// A write is in flight — buttons that would start a second one are off.
  final busy = false.obs;

  /// The server's `user_message` for the last refused action, shown once then cleared.
  final message = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  GymOverview? get ready => switch (overview.value) {
    Ready<GymOverview>(:final data) => data,
    _ => null,
  };

  /// Sends anything waiting first, so the overview it then fetches already counts it.
  Future<void> load({bool quietly = false}) async {
    // Never write an Rx in the same call stack as the caller: load is reached from a page's
    // initState and from a lazy Get.find inside a build (Home's Gym card), and a write there marks
    // every mounted Obx dirty mid-build — "setState() called during build". A microtask runs once
    // the frame in progress has finished.
    await Future<void>.value();
    if (!quietly || ready == null) overview.value = const Loading();
    active.value = await gym.activeWorkout();
    pending.value = await gym.sendPending();
    final result = await gym.overview();
    overview.value = result.fold(Failed.new, Ready.new);
    _replanReminders();
  }

  /// The workout-day reminder follows the weekly plan: weekday → routine name.
  void _replanReminders() {
    final o = ready;
    final replan = reminders;
    if (o == null || replan == null || o.fromCache) return;
    replan(
      workoutWeek: {
        for (final MapEntry(:key, :value) in o.week.entries)
          if (o.routineById(value) case final routine?) key: routine.name,
      },
    );
  }

  /// The library, fetched once per session of the screen.
  Future<void> loadExercises({bool force = false}) async {
    if (!force && exercises.value is Ready<List<Exercise>>) return;
    // Called from the library's initState: same reason as in [load].
    await Future<void>.value();
    exercises.value = const Loading();
    final result = await gym.exercises();
    exercises.value = result.fold(Failed.new, (list) => list.isEmpty ? const Empty() : Ready(list));
  }

  Future<void> refreshActive() async => active.value = await gym.activeWorkout();

  Future<bool> loadStarterPlan() => _overviewAction(gym.loadStarterPlan);

  Future<bool> setWeekday(int weekday, int? routineId) {
    final current = ready;
    if (current == null) return Future.value(false);
    final week = <int, int?>{...current.week, weekday: routineId};
    return _overviewAction(() => gym.setSchedule(week));
  }

  Future<bool> setDay(String date, {int? routineId, bool rest = false}) =>
      _overviewAction(() => gym.setDay(date: date, routineId: routineId, rest: rest));

  Future<bool> saveSettings(GymSettings settings) async {
    final ok = await _run(() => gym.updateSettings(settings));
    if (ok) await load(quietly: true);
    return ok;
  }

  Future<Routine?> saveRoutine(RoutineDraft draft) async {
    Routine? saved;
    final ok = await _run(() async {
      final result = await gym.saveRoutine(draft);
      saved = result.fold((_) => null, (r) => r);
      return result;
    });
    if (ok) await load(quietly: true);
    return saved;
  }

  Future<bool> deleteRoutine(int id) async {
    final ok = await _run(() => gym.deleteRoutine(id));
    if (ok) await load(quietly: true);
    return ok;
  }

  Future<Exercise?> saveExercise({
    required String name,
    required String bodyPart,
    String? description,
    String? id,
  }) async {
    Exercise? saved;
    final ok = await _run(() async {
      final result = id == null
          ? await gym.createExercise(name: name, bodyPart: bodyPart, description: description)
          : await gym.updateExercise(id, name: name, bodyPart: bodyPart, description: description);
      saved = result.fold((_) => null, (e) => e);
      return result;
    });
    if (ok) await loadExercises(force: true);
    return saved;
  }

  Future<bool> deleteExercise(String id) async {
    final ok = await _run(() => gym.deleteExercise(id));
    if (ok) await Future.wait([loadExercises(force: true), load(quietly: true)]);
    return ok;
  }

  /// Adds one exercise to a routine, keeping everything else about it as it was.
  Future<bool> addToRoutine(Routine routine, RoutineExercise config) async =>
      await saveRoutine(
        RoutineDraft(
          id: routine.id,
          name: routine.name,
          icon: routine.icon,
          progression: routine.progression,
          exercises: [...routine.items.map((i) => i.config), config],
        ),
      ) !=
      null;

  Future<bool> sendPending() async {
    pending.value = await gym.sendPending();
    if (pending.value == 0) await load(quietly: true);
    return pending.value == 0;
  }

  Future<bool> _overviewAction(Future<Either<Failure, GymOverview>> Function() action) async {
    GymOverview? next;
    final ok = await _run(() async {
      final result = await action();
      next = result.fold((_) => null, (o) => o);
      return result;
    });
    if (next != null) {
      overview.value = Ready(next!);
      _replanReminders();
    }
    return ok;
  }

  Future<bool> _run<T>(Future<Either<Failure, T>> Function() action) async {
    if (busy.value) return false;
    busy.value = true;
    try {
      final result = await action();
      final failure = result.fold((f) => f, (_) => null);
      if (failure != null) message.value = failure.userMessage;
      return failure == null;
    } finally {
      busy.value = false;
    }
  }
}
