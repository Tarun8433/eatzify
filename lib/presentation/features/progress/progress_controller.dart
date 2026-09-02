import 'dart:async';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';

/// Weight history behind the four states (CLAUDE.md rule 6).
///
/// docs/05 §6 shapes what this may NOT do: no streaks on weight, no leaderboards, no "missed" day.
/// The controller therefore exposes history and the server's change figure, and nothing that could
/// be rendered as a score.
///
/// D-143 adds the dashboard's raw material: the last two weeks of diary days, fetched one GET per
/// day off the server-named anchor. The averages below are display arithmetic over figures the
/// SERVER computed (sums and targets) — never a target, BMI or judgement of the client's own.
/// docs/21 names the summary endpoint that replaces this fan-out.
class ProgressController extends GetxController {
  ProgressController({required this.measurements, this.diary});

  static const weightKind = 'weight';

  /// The dashboard's section chips. Wire-ish keys; labels come from l10n (rule 4).
  static const sections = ['overview', 'nutrition', 'weight', 'activity', 'habits'];

  /// Days in the dashboard's window, and how many of them are fetched (two windows).
  static const windowDays = 7;
  static const _fetchDays = windowDays * 2;

  /// The body measurements the Result Monitor asks for, beside weight. Waist is the one that
  /// matters clinically — it tracks visceral fat, which weight alone does not — and the rest are
  /// optional progress metrics the brief marked as such.
  static const bodyKinds = ['waist', 'hip', 'thigh', 'chest'];

  /// What the `+` sheet writes every day: steps, water and calories burned (D-80, D-86).
  ///
  /// Same endpoint as the body measurements — one row per kind per diary day — so seeing them over
  /// time needed no new API, only a screen that asks. Until this, they were visible on Home for
  /// today and nowhere at all tomorrow, which is not tracking; it is a display.
  static const habitKinds = ['steps', 'water_ml', 'energy_burned_kcal'];

  final MeasurementsRepository measurements;

  /// Optional, like Home's step sync (D-99): the dashboard cards need it, the weight and habit
  /// history does not, and every existing test that is about those registers no diary.
  final DiaryRepository? diary;

  final state = Rx<ViewState<MeasurementHistory>>(const Loading());

  /// Which section chip is active. One of [sections].
  final section = 'overview'.obs;

  /// 0 is the week ending today; 1 the week before it. The pill in the heading.
  final period = 0.obs;

  /// The fetched diary days, keyed by the SERVER's diary date. A day that failed to load or was
  /// never diarised is absent — absent is "not known", never a day of zeroes.
  final days = <String, DiaryDay>{}.obs;

  /// The server-named diary date for today — the anchor every window counts back from. Rule 8:
  /// the server names today; the client only steps backwards from a day the server has named.
  final anchor = RxnString();

  /// The other measurements, keyed by kind. Deliberately NOT part of [state]: weight is what this
  /// screen is about, and a waist reading that failed to load must not blank a weight chart that
  /// arrived perfectly well.
  final body = <String, MeasurementHistory>{}.obs;

  /// The daily habits, keyed by kind. Absent means never logged, which is not the same as zero.
  final habits = <String, MeasurementHistory>{}.obs;

  final saving = false.obs;

  /// The server's `user_message`, verbatim (rule 7).
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await measurements.history(weightKind);
    state.value = result.fold(
      Failed.new,
      (history) => history.isEmpty ? const Empty() : Ready(history),
    );
    // The dashboard must not hold the weight history up (D-143), the same way Home's extras never
    // hold the day up.
    unawaited(loadWeeks());
    await Future.wait([loadBody(), loadHabits()]);
  }

  /// The last two weeks of diary days: today from the server first (it NAMES the anchor date),
  /// then the thirteen days before that anchor, in parallel. docs/21 §1 names the one-request
  /// summary endpoint that retires this fan-out.
  Future<void> loadWeeks() async {
    final d = diary;
    if (d == null) return;

    final today = await d.day();
    final anchorDate = today.fold((_) => null, (day) {
      days[day.diaryDate] = day;
      return DateTime.tryParse(day.diaryDate);
    });
    if (anchorDate == null) return;
    anchor.value = _iso(anchorDate);

    await Future.wait([
      for (var back = 1; back < _fetchDays; back++)
        d
            .day(date: _iso(anchorDate.subtract(Duration(days: back))))
            .then((r) => r.fold((_) {}, (day) => days[day.diaryDate] = day)),
    ]);
  }

  /// The seven diary days of a period, oldest first; a day the server has nothing for is null.
  /// Period 0 ends at the anchor, period 1 at the day before period 0 begins.
  List<DiaryDay?> week(int period) {
    final start = anchor.value == null ? null : DateTime.tryParse(anchor.value!);
    if (start == null) return const [];

    return [
      for (var i = windowDays - 1; i >= 0; i--)
        days[_iso(start.subtract(Duration(days: i + period * windowDays)))],
    ];
  }

  /// Days of the period with anything eaten. The denominators below are THIS, not seven: a day
  /// with no diary is "not known", and averaging it in as zero would fabricate an empty plate.
  List<DiaryDay> _fed(int period) =>
      week(period).whereType<DiaryDay>().where((d) => d.entries.isNotEmpty).toList();

  /// Mean kcal over the period's fed days — display arithmetic on server sums, or null when no
  /// day qualifies.
  double? avgKcal(int period) {
    final fed = _fed(period);
    if (fed.isEmpty) return null;
    return fed.fold<double>(0, (sum, d) => sum + d.totals.kcal) / fed.length;
  }

  /// Mean grams of each macro over the period's fed days, or null when no day qualifies.
  ({double protein, double carb, double fat})? avgMacros(int period) {
    final fed = _fed(period);
    if (fed.isEmpty) return null;
    return (
      protein: fed.fold<double>(0, (s, d) => s + d.totals.proteinG) / fed.length,
      carb: fed.fold<double>(0, (s, d) => s + d.totals.carbG) / fed.length,
      fat: fed.fold<double>(0, (s, d) => s + d.totals.fatG) / fed.length,
    );
  }

  /// The newest server-set targets across both windows. Never computed here (rule 2); null when
  /// no plan has ever answered, and every card that compares hides its comparison then.
  Macros? get latestTargets {
    for (final day in [...week(0).reversed, ...week(1).reversed]) {
      if (day?.targets != null) return day!.targets;
    }
    return null;
  }

  /// The goal line's kcal — the server's target, or null.
  double? get goalKcal {
    final kcal = latestTargets?.kcal;
    return kcal == null || kcal <= 0 ? null : kcal;
  }

  /// This week's average against last week's, as a rounded percent — or null while either week
  /// has nothing to average, which is NOT the same as zero change.
  int? get vsLastWeekPct {
    final now = avgKcal(0);
    final before = avgKcal(1);
    if (now == null || before == null || before == 0) return null;
    return ((now - before) / before * 100).round();
  }

  /// The period's seven iso diary dates, oldest first — empty until the server has named today.
  List<String> weekDates(int period) {
    final start = anchor.value == null ? null : DateTime.tryParse(anchor.value!);
    if (start == null) return const [];
    return [
      for (var i = windowDays - 1; i >= 0; i--)
        _iso(start.subtract(Duration(days: i + period * windowDays))),
    ];
  }

  /// Diary dates in period 0 with anything logged — eaten entries, or any habit measurement.
  Set<String> get loggedThisWeek {
    final logged = <String>{
      for (final day in week(0).whereType<DiaryDay>())
        if (day.entries.isNotEmpty) day.diaryDate,
      for (final history in habits.values)
        for (final point in history.points) point.diaryDate,
    };
    return logged.intersection(weekDates(0).toSet());
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// One request per kind, in parallel. A kind with no readings is simply absent from the map —
  /// the screen offers to start it rather than drawing an empty chart.
  Future<void> loadBody() async => body.assignAll(await _historiesFor(bodyKinds));

  Future<void> loadHabits() async => habits.assignAll(await _historiesFor(habitKinds));

  /// One request per kind, in parallel. A kind with no readings is simply absent from the map —
  /// the screen says so rather than drawing a chart of nothing, and a kind that failed to load is
  /// absent too rather than rendering as zero.
  Future<Map<String, MeasurementHistory>> _historiesFor(List<String> kinds) async {
    final loaded = await Future.wait(
      kinds.map((kind) async => MapEntry(kind, await measurements.history(kind))),
    );

    return {
      for (final entry in loaded)
        if (entry.value.fold((_) => null, (h) => h.isEmpty ? null : h) case final h?) entry.key: h,
    };
  }

  /// Returns true when the server flagged the value as implausible, so the caller can ask the user
  /// to confirm. docs/09 §4: the value is already stored — this is a "did you mean that?", not a
  /// rejection, and the user is never blocked from recording their own weight.
  Future<bool?> record(double kg) => recordKind(weightKind, kg, unit: 'kg');

  /// Records any measurement this screen shows. Weight is in kg, the body measurements in cm — the
  /// server refuses a mismatch (D-80), so the unit travels with the call rather than being guessed.
  Future<bool?> recordKind(
    String kind,
    double value, {
    required String unit,

    /// When the reading was taken, if not now. The server still decides the diary day (rule 8).
    DateTime? at,
  }) async {
    saving.value = true;
    error.value = null;

    final result = await measurements.record(kind: kind, value: value, unit: unit, at: at);
    saving.value = false;

    // fold stays synchronous; the reload happens after, so `load()` is not awaited inside it.
    final suspect = result.fold((failure) {
      error.value = failure.userMessage;
      return null;
    }, (ok) => ok.isSuspect);

    if (suspect == null) return null;

    await load();
    return suspect;
  }
}
