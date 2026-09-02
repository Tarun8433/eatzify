import 'dart:io';

import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';

/// Copies the phone's step count into today's diary (D-98).
///
/// Pure orchestration, no I/O of its own and no Flutter — it is the one place the rules about WHEN
/// a sync may write live, so they can be tested without a device, which is the only way they can
/// be tested at all.
///
/// **It never decides which day a walk belongs to.** The window comes from the server on the diary
/// day (rule 8); with no window there is no sync, because a guessed one would file a 1 a.m. walk
/// under tomorrow on some phones and today on others.
///
/// **It never overwrites a hand-typed figure.** The server enforces that (D-97), but this checks
/// too — not for safety, for silence: without it every foreground would fire a write the server
/// discards, which is a request per launch for nothing.
class SyncSteps {
  const SyncSteps({required this.health, required this.measurements});

  final HealthRepository health;
  final MeasurementsRepository measurements;

  Future<SyncStepsResult> call(DiaryDay day) async {
    final start = day.windowStart;
    final end = day.windowEnd;
    if (start == null || end == null) return SyncStepsResult.noWindow;

    // A correction someone made by hand outranks the phone for the rest of the day (D-97).
    if (day.stepsSource == MeasurementSource.manual && day.steps != null) {
      return SyncStepsResult.deferredToManual;
    }

    if (await health.availability() != HealthAvailability.ready) {
      return SyncStepsResult.unavailable;
    }
    // Never prompts here. A permission sheet must follow a tap, not an app launch.
    if (!await health.hasStepPermission()) return SyncStepsResult.notPermitted;

    final read = await health.stepsBetween(start, end);
    return read.fold((_) => SyncStepsResult.failed, (steps) async {
      // Null is "the platform has no answer", which is not zero and must not be stored as one.
      if (steps == null) return SyncStepsResult.nothingToWrite;
      // Nor is an unchanged count worth a request.
      if (steps == day.steps) return SyncStepsResult.unchanged;

      final written = await measurements.record(
        kind: 'steps',
        value: steps.toDouble(),
        unit: 'steps',
        source: platformSource,
      );
      return written.fold((_) => SyncStepsResult.failed, (_) => SyncStepsResult.written);
    });
  }

  /// Which store the reading came from. The server keeps these apart so a user can be told which
  /// app to correct, and so a phone that changed platforms is still not mistaken for a person.
  static MeasurementSource get platformSource =>
      Platform.isIOS ? MeasurementSource.appleHealth : MeasurementSource.healthConnect;
}

/// Every way a sync can end. An enum rather than a bool because most of these are NOT errors —
/// "the user has not connected anything" is the normal state of most installs, and a caller that
/// could only tell success from failure would show a warning for it.
enum SyncStepsResult {
  written,

  /// Already correct. Nothing sent.
  unchanged,

  /// The user typed their own figure today; the phone does not get to argue until tomorrow.
  deferredToManual,

  /// No health store, or Health Connect is not installed.
  unavailable,

  /// Never asked, or refused. Manual entry still works, so this is not a problem to report.
  notPermitted,

  /// The platform returned nothing. Different from zero steps.
  nothingToWrite,

  /// The server did not send a diary window — an older API. Sync is skipped rather than guessed.
  noWindow,

  /// The read or the write failed. Silent: the next foreground tries again, and there is nothing
  /// the user can do about it in the meantime.
  failed;

  /// Whether Home needs to reload. Only one outcome changed anything.
  bool get changedTheDay => this == written;
}
