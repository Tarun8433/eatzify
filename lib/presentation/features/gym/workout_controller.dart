import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/gym/gym_enums.dart';
import 'package:health_pro/domain/entities/gym/gym_overview.dart';
import 'package:health_pro/domain/entities/gym/workout.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/usecases/workout_session.dart';
import 'package:health_pro/presentation/features/gym/workout_feedback.dart';

/// Something the screen should tell the person about, once.
enum WorkoutEventKind { restOver, cardioLogged, holdLogged, askWorkingWeight, allDone }

class WorkoutEvent {
  WorkoutEvent(this.kind, [this.entry]);

  final WorkoutEventKind kind;
  final int? entry;
}

/// A timed hold in progress: which set, and when its countdown reaches zero.
typedef WorkTimer = ({int entry, int set, int target, DateTime endsAt});

/// The workout screen (ADR-013). The session itself is the immutable [WorkoutSession]; this adds
/// the clocks — rest and timed holds, both kept as wall-clock END times so a phone put in a pocket
/// counts correctly when it comes back — and saves the session to the phone after every change.
class WorkoutController extends FullLifeCycleController with FullLifeCycleMixin {
  WorkoutController({
    required this.gym,
    required this.feedback,
    required WorkoutSession session,
    required this.settings,
    required this.restAlert,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       session = Rx<WorkoutSession>(session);

  final GymRepository gym;
  final WorkoutFeedback feedback;
  final GymSettings settings;

  /// Title and body for the background rest notification, already in the person's language.
  final ({String title, String body}) restAlert;
  final DateTime Function() _clock;

  final Rx<WorkoutSession> session;
  late final now = _clock().obs;

  final restEndsAt = Rxn<DateTime>();
  int restTotalSec = 0;
  final work = Rxn<WorkTimer>();

  final event = Rxn<WorkoutEvent>();
  final saving = false.obs;

  Timer? _ticker;
  int _lastRestBeep = -1;

  static const _tick = Duration(seconds: 1);
  static const _restStep = 15;
  static const _restCountdownFrom = 3;

  @override
  void onInit() {
    super.onInit();
    unawaited(feedback.keepAwake(on: settings.keepAwake));
    _ticker = Timer.periodic(_tick, (_) => _onTick());
  }

  @override
  void onClose() {
    _ticker?.cancel();
    unawaited(feedback.keepAwake(on: false));
    unawaited(feedback.cancelRestAlert());
    super.onClose();
  }

  // --- the background notification: only while the app is not on screen ---
  @override
  void onPaused() {
    final ends = restEndsAt.value;
    if (ends != null) {
      unawaited(feedback.scheduleRestAlert(ends, title: restAlert.title, body: restAlert.body));
    }
  }

  @override
  void onResumed() {
    unawaited(feedback.cancelRestAlert());
    _onTick();
  }

  @override
  void onDetached() {}

  @override
  void onInactive() {}

  @override
  void onHidden() {}

  // --- reading ---
  int get restRemaining =>
      restEndsAt.value == null ? 0 : max(0, restEndsAt.value!.difference(now.value).inSeconds);

  int get workRemaining =>
      work.value == null ? 0 : max(0, work.value!.endsAt.difference(now.value).inSeconds);

  Duration get elapsed => session.value.elapsed(now.value);

  bool get effortOn => settings.effortScale != EffortScale.off;

  // --- sets ---
  void toggle(int entry, int set) {
    final wasDone = session.value.entries[entry].sets[set].done;
    final (next, outcome) = session.value.toggle(entry, set);
    _save(next);
    if (wasDone) return;
    unawaited(feedback.setChecked(sound: settings.sound));
    _afterCheck(entry, outcome);
  }

  void setValue(int entry, int set, WorkoutSet value) =>
      _save(session.value.withSet(entry, set, value));

  void addSet(int entry) => _save(session.value.addSet(entry));

  void removeSet(int entry) => _save(session.value.removeSet(entry));

  void addEntry(SessionEntry entry) => _save(session.value.addEntry(entry));

  void goTo(int group) => _save(session.value.goTo(group));

  void next() => goTo(session.value.currentGroupIndex + 1);

  void previous() => goTo(session.value.currentGroupIndex - 1);

  void confirmWorkingWeight(int entry, double kg) {
    _save(session.value.confirmWorkingWeight(entry, kg));
    _afterWeight();
  }

  void skipWorkingWeight(int entry) {
    _save(session.value.markAsked(entry));
    _afterWeight();
  }

  // --- rest ---
  void startRest([int? seconds]) {
    restTotalSec = seconds ?? settings.restSec;
    restEndsAt.value = _clock().add(Duration(seconds: restTotalSec));
    _lastRestBeep = -1;
  }

  void adjustRest(int delta) {
    final ends = restEndsAt.value;
    if (ends == null) return;
    final moved = ends.add(Duration(seconds: delta));
    if (!moved.isAfter(_clock())) {
      skipRest();
      return;
    }
    restTotalSec = max(restTotalSec + delta, 1);
    restEndsAt.value = moved;
  }

  void addRest() => adjustRest(_restStep);

  void cutRest() => adjustRest(-_restStep);

  void skipRest() {
    restEndsAt.value = null;
    unawaited(feedback.cancelRestAlert());
  }

  // --- timed holds ---
  void startHold(int entry, int set) {
    skipRest();
    final target = session.value.entries[entry].sets[set].seconds ?? 0;
    if (target <= 0) return;
    work.value = (
      entry: entry,
      set: set,
      target: target,
      endsAt: _clock().add(Duration(seconds: target)),
    );
  }

  /// Logs the seconds actually held — at least one — and ticks the set off.
  void finishHold() {
    final w = work.value;
    if (w == null) return;
    final held = max(1, w.target - workRemaining);
    work.value = null;
    final current = session.value.entries[w.entry].sets[w.set];
    _save(session.value.withSet(w.entry, w.set, current.copyWith(seconds: held)));
    if (!current.done) toggle(w.entry, w.set);
  }

  void cancelHold() => work.value = null;

  // --- the end ---
  /// Saves the workout. Returns the server's detail, or null when it was kept on the phone to send
  /// later (no signal) — the queue in the repository already holds it either way.
  Future<({WorkoutDetail? detail, Failure? failure})> finish() async {
    saving.value = true;
    skipRest();
    work.value = null;
    try {
      final result = await gym.saveWorkout(session.value.finish(_clock()));
      return await result.fold(
        (failure) async {
          // No signal: it is queued and will be sent — the session is done from the person's side.
          if (failure is OfflineFailure) await gym.saveActiveWorkout(null);
          return (detail: null, failure: failure);
        },
        (detail) async {
          await gym.saveActiveWorkout(null);
          unawaited(feedback.workoutSaved(sound: settings.sound));
          return (detail: detail, failure: null);
        },
      );
    } finally {
      saving.value = false;
    }
  }

  Future<void> discard() async {
    skipRest();
    await gym.saveActiveWorkout(null);
  }

  void _afterCheck(int entry, CheckOutcome outcome) {
    final s = session.value;
    if (outcome.rest) {
      startRest();
    } else if (outcome.groupFinished) {
      skipRest();
    }
    if (!outcome.entryFinished) return;
    final mode = s.entries[entry].mode;
    if (s.asksWorkingWeight(entry)) {
      event.value = WorkoutEvent(WorkoutEventKind.askWorkingWeight, entry);
      return;
    }
    if (mode == ExerciseMode.cardio) event.value = WorkoutEvent(WorkoutEventKind.cardioLogged);
    if (mode == ExerciseMode.time) event.value = WorkoutEvent(WorkoutEventKind.holdLogged);
    if (outcome.allFinished) {
      event.value = WorkoutEvent(WorkoutEventKind.allDone);
    } else if (outcome.groupFinished) {
      next();
    }
  }

  void _afterWeight() {
    final s = session.value;
    if (s.allDone) {
      event.value = WorkoutEvent(WorkoutEventKind.allDone);
    } else if (s.isGroupDone(s.currentGroupIndex)) {
      next();
    }
  }

  void _onTick() {
    now.value = _clock();
    final remaining = restRemaining;
    if (restEndsAt.value != null) {
      if (remaining <= 0) {
        restEndsAt.value = null;
        unawaited(feedback.restOver(sound: settings.sound));
        event.value = WorkoutEvent(WorkoutEventKind.restOver);
      } else if (remaining <= _restCountdownFrom && remaining != _lastRestBeep) {
        _lastRestBeep = remaining;
        unawaited(feedback.restEnding(sound: settings.sound));
      }
    }
    if (work.value != null && workRemaining <= 0) finishHold();
  }

  void _save(WorkoutSession next) {
    session.value = next;
    // Fire and forget: the phone's copy is a safety net, never something to wait on mid-set.
    unawaited(gym.saveActiveWorkout(next).catchError((Object _) {}));
  }
}
