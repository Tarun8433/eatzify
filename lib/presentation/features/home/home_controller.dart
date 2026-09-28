import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/home_widget/home_screen_widget.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/reminder.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';

/// Today's diary. docs/09 §5 — the day boundary is the server's, never computed here.
class HomeController extends FullLifeCycleController with FullLifeCycleMixin {
  HomeController({
    required this.diary,
    required this.plans,
    this.syncHealth,
    this.measurements,
    this.reminders,
  });

  final DiaryRepository diary;
  final PlanRepository plans;

  /// Optional, like [syncHealth]: only the streak card needs it, and Home works without one.
  final MeasurementsRepository? measurements;

  /// Optional: null in every test that is not about syncing. Home works identically without it,
  /// which is the point — activity is something the day may carry, never something it waits for.
  final SyncHealth? syncHealth;

  /// Optional likewise. Every log reloads Home, so this is where the week of reminders is re-planned
  /// from what today now holds (D-222).
  final RefreshReminders? reminders;

  final state = Rx<ViewState<DiaryDay>>(const Loading());

  /// Whether to offer connecting a health app under the day's activity (D-215). Only after a sync
  /// has said "not permitted" — never guessed, and never on a phone with nothing to connect.
  final healthOffer = false.obs;

  /// Whether a health app is connected, so Home offers a Sync instead (D-218).
  final healthLinked = false.obs;

  /// Raised once per account, the first time a sync finds nothing connected: the page shows the
  /// "fill in your activity automatically" sheet and lowers it again.
  final healthPrompt = false.obs;

  /// A tapped sync is running. The button waits rather than stacking requests.
  final syncing = false.obs;

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

  /// Someone who walked all afternoon and comes back to the app should see it (D-215). A sync,
  /// not a reload: the day is already on screen, and a skeleton on every return would be worse
  /// than a number that updates when there is a new one.
  @override
  void onResumed() {
    if (isToday) unawaited(_syncHealth());
    // Every open moves the week of reminders along, whichever day is on screen.
    unawaited(_replan(null));
  }

  @override
  void onPaused() {}

  @override
  void onInactive() {}

  @override
  void onDetached() {}

  @override
  void onHidden() {}

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

  /// [quietly] keeps what is on screen while the new day loads — for a refresh nobody asked for.
  Future<void> load({bool quietly = false}) async {
    if (!quietly) state.value = const Loading();
    final result = await diary.day(date: _dateArgument());
    // A day with no entries is Ready, not Empty: the targets and the "nothing logged yet" line are
    // both real content. Empty would hide the plan the user is trying to follow.
    state.value = result.fold(Failed.new, Ready.new);

    // Today's figures go out to the home screen (D-210). Only for TODAY: a widget showing last
    // Tuesday because somebody browsed back to it would be lying about right now.
    if (isToday) unawaited(_publishToHomeScreen());
    final loaded = state.value;
    if (isToday && loaded is Ready<DiaryDay>) {
      unawaited(_replan(ReminderDay.fromDiary(loaded.data)));
    }

    unawaited(_loadExtras());

    // Only today is the phone's to copy on a load. Earlier days are filled once, by the backfill
    // that runs when someone connects — not by browsing back to them.
    if (isToday) unawaited(_syncHealth());
  }

  /// Never fails Home: a reminder that could not be re-planned rings as it was planned before.
  Future<void> _replan(ReminderDay? today) async {
    try {
      await reminders?.call(today: today);
    } on Object {
      // Nothing to show. The next load tries again.
    }
  }

  /// Push the day to the home-screen widget.
  ///
  /// Never holds the screen up and never fails it: a widget that could not be refreshed is a
  /// widget showing an older number, which is a great deal better than a Home tab that would not
  /// load because a launcher was busy.
  Future<void> _publishToHomeScreen() async {
    final current = state.value;
    if (current is! Ready<DiaryDay>) return;

    final day = current.data;

    try {
      await HomeScreenWidget.publish(
        waterMl: day.waterLoggedMl,
        waterTargetMl: day.waterTargetMl,
        steps: day.steps,
        kcal: day.totals.kcal.round(),
        kcalTarget: day.targets?.kcal.round(),
        burnedKcal: day.energyBurnedKcal,
      );
    } on Object {
      // Deliberately swallowed. There is nothing a user could do about it and nothing worth
      // showing them; the next load tries again.
    }
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

  /// Copies the phone's activity into today, AFTER the day is on screen (D-214).
  ///
  /// Never awaited by [load]: a diary that waited on a motion query would show a spinner for
  /// something the user did not ask for, and would show it forever on a phone that never answers.
  /// The day is rendered either way; the figures arrive, or they do not.
  ///
  /// This cannot recurse. `SyncHealth` remembers what it sent and returns `unchanged` for the same
  /// figures, so the reload it triggers cannot trigger another write.
  Future<void> _syncHealth() async {
    final sync = syncHealth;
    final current = state.value;
    if (sync == null || current is! Ready<DiaryDay>) return;

    final result = await sync(current.data);
    _showHealthState(result);
    if (result == SyncHealthResult.notPermitted) unawaited(_offerOnce(sync));
    if (result.changedTheDay) await load(quietly: true);
  }

  /// Connect or Sync, tapped on Home (D-218). Returns the outcome so the page can say what
  /// happened; null when nothing ran.
  Future<SyncHealthResult?> syncHealthNow() async {
    final sync = syncHealth;
    if (sync == null || syncing.value) return null;

    syncing.value = true;
    try {
      final result = await sync.syncNow();
      _showHealthState(result);
      if (result.changedTheDay) await load(quietly: true);
      return result;
    } finally {
      syncing.value = false;
    }
  }

  /// The page has put the sheet up.
  void healthPromptShown() => healthPrompt.value = false;

  void _showHealthState(SyncHealthResult result) {
    // A failed read or write says nothing new about the connection; keep what was known.
    if (result == SyncHealthResult.readFailed || result == SyncHealthResult.sendFailed) return;
    healthOffer.value = result == SyncHealthResult.notPermitted;
    healthLinked.value = result.isConnected;
  }

  /// Once per account, whatever the answer: a sheet that comes back every launch is nagging.
  Future<void> _offerOnce(SyncHealth sync) async {
    if (await sync.health.wasOffered()) return;
    await sync.health.markOffered();
    healthPrompt.value = true;
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
