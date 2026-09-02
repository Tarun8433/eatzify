import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/usecases/sync_steps.dart';

/// Today's diary. docs/09 §5 — the day boundary is the server's, never computed here.
class HomeController extends GetxController {
  HomeController({required this.diary, required this.plans, this.syncSteps, this.measurements});

  final DiaryRepository diary;
  final PlanRepository plans;

  /// Optional, like [syncSteps]: only the streak card needs it, and Home works without one.
  final MeasurementsRepository? measurements;

  /// Optional: null on a platform with no step counter, and in every test that is not about
  /// syncing. Home works identically without it, which is the point — a step count is something
  /// the day may carry, never something it waits for.
  final SyncSteps? syncSteps;

  final state = Rx<ViewState<DiaryDay>>(const Loading());

  /// Diary dates (`yyyy-MM-dd`) with at least one logged measurement — the streak's raw material.
  final loggedDates = <String>{}.obs;

  /// How many days back from today is on screen. Zero is today, and today is where it opens.
  ///
  /// A COUNT rather than a date, because the client does not own the calendar: the server decides
  /// where a diary day begins (04:00 IST, rule 8), and the app only ever says "the day before the
  /// one I am looking at".
  final daysBack = 0.obs;

  /// How far back the diary can be read. Ninety days is what the measurement history returns and
  /// what the 48-hour edit lock makes worth looking at; beyond that a user is browsing, not
  /// tracking.
  static const maxDaysBack = 90;

  bool get isToday => daysBack.value == 0;
  final generating = false.obs;

  /// The server's `user_message`, verbatim — including the docs/05 §7 referral copy when a gate
  /// blocks the plan (rule 7).
  final planError = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// One day earlier. Stops at [maxDaysBack] rather than paging into an empty past.
  Future<void> showEarlierDay() async {
    if (daysBack.value >= maxDaysBack) return;
    daysBack.value++;
    await load();
  }

  /// One day later, never past today — there is no diary for tomorrow.
  Future<void> showLaterDay() async {
    if (isToday) return;
    daysBack.value--;
    await load();
  }

  Future<void> backToToday() async {
    if (isToday) return;
    daysBack.value = 0;
    await load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await diary.day(date: _dateArgument());
    // A day with no entries is Ready, not Empty: the targets and the "nothing logged yet" line are
    // both real content. Empty would hide the plan the user is trying to follow.
    state.value = result.fold(Failed.new, Ready.new);

    unawaited(_loadExtras());

    // Only today's step count is the phone's to copy. Yesterday's is history, and a sync that
    // wrote into it would overwrite a day the user can no longer see being changed.
    if (isToday) unawaited(_syncSteps());
  }

  /// What surrounds the diary — today only the streak's histories (D-140: the meals section shows
  /// what was EATEN, which the day itself carries). Nothing here may hold the day up.
  Future<void> _loadExtras() async {
    final work = <Future<void>>[];

    final m = measurements;
    if (m != null) {
      // Any measurement makes a day "logged". Food-only days are counted for TODAY through the
      // diary itself; counting them for past days needs a server endpoint (D-138 names it), and
      // until then a day the streak cannot see is shown NEUTRALLY, never as a failure.
      for (final kind in const ['water_ml', 'steps', 'energy_burned_kcal']) {
        work.add(
          m
              .history(kind)
              .then(
                (r) => r.fold((_) {}, (history) {
                  loggedDates.addAll(history.points.map((p) => p.diaryDate));
                }),
              ),
        );
      }
    }

    await Future.wait(work);
  }

  /// Consecutive logged days ending at [today] (the server's diary date) — or at yesterday, so
  /// the streak does not read as broken before breakfast.
  int streakEndingAt(String today) {
    final logged = {...loggedDates};
    final day = state.value;
    if (day is Ready<DiaryDay> && day.data.entries.isNotEmpty) logged.add(today);

    var date = DateTime.tryParse(today);
    if (date == null) return 0;
    if (!logged.contains(today)) date = date.subtract(const Duration(days: 1));

    var run = 0;
    while (logged.contains(_iso(date!))) {
      run++;
      date = date.subtract(const Duration(days: 1));
    }
    return run;
  }

  /// `yyyy-MM-dd` for a date already anchored to a server-named diary day.
  static String isoDate(DateTime d) => _iso(d);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `yyyy-MM-dd`, or null for today. Null is not the same as today's date spelled out: the server
  /// resolves "today" against the diary boundary, and a client that spells it out has guessed.
  String? _dateArgument() {
    if (isToday) return null;
    final day = DateTime.now().subtract(Duration(days: daysBack.value));
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  /// Copies the phone's step count into today, AFTER the day is on screen (D-99).
  ///
  /// Never awaited by [load]: a diary that waited on a motion query would show a spinner for
  /// something the user did not ask for, and would show it forever on a phone that never answers.
  /// The day is rendered either way; a step count arrives, or it does not.
  ///
  /// This cannot recurse. `SyncSteps` returns `unchanged` when the count already matches, so the
  /// reload it triggers cannot trigger another write.
  Future<void> _syncSteps() async {
    final sync = syncSteps;
    final current = state.value;
    if (sync == null || current is! Ready<DiaryDay>) return;

    final result = await sync(current.data);
    if (result.changedTheDay) await load();
  }

  /// docs/09 §4.2. On success the day is re-read rather than patched locally — the targets are the
  /// server's, and guessing them here would be the client computing a target (CLAUDE.md rule 2).
  Future<void> generatePlan() async {
    if (generating.value) return;

    generating.value = true;
    planError.value = null;
    final result = await plans.generate();
    generating.value = false;

    final failed = result.fold((f) => f.userMessage, (_) => null);
    if (failed != null) {
      planError.value = failed;
      return;
    }

    await load();
  }
}
