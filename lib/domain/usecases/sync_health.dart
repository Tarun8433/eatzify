import 'dart:io';

import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';

/// Copies what the phone recorded — steps, active calories, distance — onto the server (D-214).
///
/// Pure orchestration, no I/O of its own and no Flutter. It is the one place the rules about WHEN a
/// sync may write live, so they can be tested without a device, which is the only way they can be
/// tested at all.
///
/// **It never decides which day a walk belongs to.** Every window comes from the server (rule 8).
///
/// Two ways in, and the difference is who asked:
///
///  - [call] runs by itself on every foreground. It never prompts and never replaces a figure
///    someone typed (D-97) — a background job does not get to overrule a person.
///  - [syncNow] runs because the person tapped Connect or Sync (D-218). It may ask for access, and
///    today's device figures replace what they typed, because asking for the device's number is
///    exactly what the tap means.
class SyncHealth {
  SyncHealth({required this.health, required this.measurements, required this.diary});

  final HealthRepository health;
  final MeasurementsRepository measurements;
  final DiaryRepository diary;

  /// How far back a tap fills in. Health Connect grants 30 days of history without an extra
  /// permission the app deliberately does not ask for.
  static const backfillDays = 30;

  /// What this instance last sent, per diary day and metric.
  ///
  /// Memory, not storage: it only has to stop a sync, and the reload a write triggers, from sending
  /// the same figures again. The server already holds the truth; losing this on a restart costs
  /// one request.
  final _sent = <String, num>{};

  /// Today, from the day the server just sent. Runs on every foreground.
  Future<SyncHealthResult> call(DiaryDay day) async {
    final start = day.windowStart;
    final end = day.windowEnd;
    if (start == null || end == null) return SyncHealthResult.noWindow;

    if (await health.availability() != HealthAvailability.ready) {
      return SyncHealthResult.unavailable;
    }
    // Never prompts here. A permission sheet must follow a tap, not an app launch.
    if (!(await health.permission()).mayRead) return SyncHealthResult.notPermitted;

    return _send([DiaryWindow(diaryDate: day.diaryDate, start: start, end: end)], today: day);
  }

  /// The last [backfillDays] days, today included, because the person asked.
  ///
  /// Safe to repeat: the server keeps one reading per kind per day, so a second run rewrites the
  /// same figures. Only TODAY's may replace a typed figure — the tap is about now, and quietly
  /// undoing last week's corrections is not what anyone meant by it.
  Future<SyncHealthResult> syncNow() async {
    if (await health.availability() != HealthAvailability.ready) {
      return SyncHealthResult.unavailable;
    }

    // The tap is what makes asking acceptable. On iOS this also covers a reinstall, where the app
    // still remembers connecting but HealthKit has forgotten — asking again is silent once it is
    // settled, and shows the sheet only when it is not.
    var permission = await health.permission();
    if (permission != HealthPermission.granted) permission = await health.requestPermission();
    if (!permission.mayRead) return SyncHealthResult.notPermitted;

    final windows = await diary.windows(backfillDays);
    return windows.fold(
      (_) async => SyncHealthResult.sendFailed,
      (windows) => _send(windows, replaceToday: windows.isEmpty ? null : windows.last.diaryDate),
    );
  }

  /// [today] is the day on screen, for a background sync's "is this already there" checks.
  /// [replaceToday] is the diary date whose typed figures a tap may replace.
  Future<SyncHealthResult> _send(
    List<DiaryWindow> windows, {
    DiaryDay? today,
    String? replaceToday,
  }) async {
    final explicit = replaceToday != null;

    final read = await health.readDaily(windows);
    final totals = read.fold((_) => null, (t) => t);
    if (totals == null) return SyncHealthResult.readFailed;
    if (totals.values.every((day) => day.isEmpty)) return SyncHealthResult.nothingToWrite;

    // Whole units: a step, a kilocalorie, a metre. Finer than that is noise the platform invented.
    final pending = <String, NewMeasurement>{
      for (final window in windows)
        for (final MapEntry(key: metric, value: raw) in (totals[window.diaryDate] ?? {}).entries)
          if (explicit || _shouldSend(window.diaryDate, metric, raw.round(), today))
            _key(window.diaryDate, metric.kind): (
              kind: metric.kind,
              value: raw.round().toDouble(),
              unit: metric.unit,
              source: platformSource,
              // The window's first instant belongs to that window's day — the server turns it
              // back into the same diary date, and nothing here had to know where the day began.
              at: window.start,
              replaceManual: window.diaryDate == replaceToday,
            ),
    };
    if (pending.isEmpty) return SyncHealthResult.unchanged;

    final written = await measurements.recordMany(pending.values.toList());
    if (written.isLeft()) return SyncHealthResult.sendFailed;

    pending.forEach((key, reading) => _sent[key] = reading.value);
    return SyncHealthResult.written;
  }

  bool _shouldSend(String diaryDate, HealthMetric metric, int value, DiaryDay? today) {
    if (_sent[_key(diaryDate, metric.kind)] == value) return false;
    if (today == null || today.diaryDate != diaryDate) return true;

    return switch (metric) {
      // A total someone typed outranks the phone for the rest of the day (D-97). An addition does
      // not: it is stored apart and sits on top of whatever the phone counts (D-221), so the day's
      // figure is compared without it.
      HealthMetric.steps => switch (today) {
        DiaryDay(steps: null) => true,
        DiaryDay(:final steps?, stepsAdded: null) =>
          today.stepsSource != MeasurementSource.manual && steps != value,
        DiaryDay(:final steps?, :final stepsAdded?) => steps - stepsAdded != value,
      },
      HealthMetric.activeEnergy => today.energyBurnedKcal != value,
      // The day does not carry a distance, so only this instance's memory can say it is unchanged.
      HealthMetric.distance => true,
    };
  }

  static String _key(String diaryDate, String kind) => '$diaryDate|$kind';

  /// Which store the reading came from. The server keeps these apart so a user can be told which
  /// app to correct, and so a phone that changed platforms is still not mistaken for a person.
  static MeasurementSource get platformSource =>
      Platform.isIOS ? MeasurementSource.appleHealth : MeasurementSource.healthConnect;
}

/// Every way a sync can end. An enum rather than a bool because most of these are NOT errors —
/// "the user has not connected anything" is the normal state of most installs, and a caller that
/// could only tell success from failure would show a warning for it.
enum SyncHealthResult {
  written,

  /// Everything the phone reported is already on the server, or is a figure someone typed.
  unchanged,

  /// No health store, or Health Connect is not installed.
  unavailable,

  /// Never connected, or refused. Manual entry still works, so this is not a problem to report.
  notPermitted,

  /// The phone recorded nothing in these windows. Different from recording zero.
  nothingToWrite,

  /// The server did not send a diary window — an older API. Skipped rather than guessed.
  noWindow,

  /// The phone's health store would not answer (D-218). Kept apart from [sendFailed] because the
  /// two want different advice: one is "try again in a moment", the other "check your connection".
  readFailed,

  /// Eatzify's server could not be reached, for the windows or for the write.
  sendFailed;

  /// Whether Home needs to reload. Only one outcome changed anything.
  bool get changedTheDay => this == written;

  /// Whether the phone is connected, as far as this outcome shows.
  bool get isConnected => switch (this) {
    notPermitted || unavailable || noWindow => false,
    _ => true,
  };
}
