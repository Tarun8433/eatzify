import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/usecases/sync_steps.dart';

import '../fakes.dart';

/// D-98. Every rule about WHEN a sync may write lives in `SyncSteps`, so that it can be tested
/// without a phone — which is the only way it can be tested at all. The platform call itself is
/// one line behind `HealthRepository` and needs a device; everything that decides whether to make
/// that call is here.

class _FakeHealth implements HealthRepository {
  // Mutable fields rather than constructor arguments: each test changes the one condition it is
  // about, which reads as "given permission is refused" instead of a row of defaults restated.
  HealthAvailability available = HealthAvailability.ready;
  bool permitted = true;
  Either<Failure, int?> steps = const Right(9500);

  int reads = 0;
  int prompts = 0;

  @override
  Future<HealthAvailability> availability() async => available;

  @override
  Future<bool> hasStepPermission() async => permitted;

  @override
  Future<bool> requestStepPermission() async {
    prompts++;
    return permitted;
  }

  @override
  Future<Either<Failure, int?>> stepsBetween(DateTime start, DateTime end) async {
    reads++;
    return steps;
  }
}

/// A day as the server sends it: the window is the server's, never the client's (rule 8).
DiaryDay dayWith({
  int? steps,
  MeasurementSource source = MeasurementSource.manual,
  bool window = true,
}) => DiaryDay(
  diaryDate: '2026-08-31',
  entries: const [],
  totals: const Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
  steps: steps,
  stepsSource: source,
  windowStart: window ? DateTime.utc(2026, 8, 30, 22, 30) : null,
  windowEnd: window ? DateTime.utc(2026, 8, 31, 22, 30) : null,
);

void main() {
  late _FakeHealth health;
  late FakeMeasurementsRepository measurements;
  late SyncSteps sync;

  setUp(() {
    health = _FakeHealth();
    measurements = FakeMeasurementsRepository();
    sync = SyncSteps(health: health, measurements: measurements);
  });

  test('writes the phone count into a day nobody has recorded', () async {
    expect(await sync(dayWith()), SyncStepsResult.written);
    expect(measurements.lastRecorded, 9500);
    expect(
      measurements.lastSource?.isAutomatic,
      isTrue,
      reason: 'labelled as a device, not a person',
    );
  });

  test('refreshes an earlier reading from the same phone', () async {
    final day = dayWith(steps: 4000, source: MeasurementSource.appleHealth);
    expect(await sync(day), SyncStepsResult.written);
    expect(measurements.lastRecorded, 9500, reason: 'a step count grows through the day');
  });

  test('leaves a hand-typed figure alone, without asking the server', () async {
    final day = dayWith(steps: 8000);

    expect(await sync(day), SyncStepsResult.deferredToManual);
    expect(measurements.lastRecorded, isNull, reason: 'the server would refuse it anyway (D-97)');
    expect(health.reads, 0, reason: 'and reading the phone first would be work for nothing');
  });

  test('does not guess the diary day when the server did not send one', () async {
    expect(await sync(dayWith(window: false)), SyncStepsResult.noWindow);
    expect(health.reads, 0, reason: 'rule 8: the 04:00 IST boundary lives in one place');
  });

  test('never prompts for permission on its own', () async {
    health.permitted = false;

    expect(await sync(dayWith()), SyncStepsResult.notPermitted);
    expect(health.prompts, 0, reason: 'a permission sheet follows a tap, not an app launch');
    expect(measurements.lastRecorded, isNull);
  });

  test('skips a phone with no health store', () async {
    health.available = HealthAvailability.unsupported;
    expect(await sync(dayWith()), SyncStepsResult.unavailable);
    expect(health.reads, 0);
  });

  test('treats "no answer" as no answer, not as zero steps', () async {
    health.steps = const Right(null);

    expect(await sync(dayWith()), SyncStepsResult.nothingToWrite);
    expect(
      measurements.lastRecorded,
      isNull,
      reason: 'storing 0 would say "you did not move", which is a different claim',
    );
  });

  test('stores a genuine zero, which is not the same thing', () async {
    health.steps = const Right(0);
    expect(
      await sync(dayWith(steps: 500, source: MeasurementSource.appleHealth)),
      SyncStepsResult.written,
    );
    expect(measurements.lastRecorded, 0);
  });

  test('does not send an unchanged count', () async {
    final day = dayWith(steps: 9500, source: MeasurementSource.appleHealth);
    expect(await sync(day), SyncStepsResult.unchanged);
    expect(measurements.lastRecorded, isNull, reason: 'a request per foreground for nothing');
  });

  test('a failed read is silent, not an error on screen', () async {
    health.steps = const Left(UnexpectedFailure('boom'));
    expect(await sync(dayWith()), SyncStepsResult.failed);
  });

  test('only a write asks Home to reload', () async {
    for (final result in SyncStepsResult.values) {
      expect(result.changedTheDay, result == SyncStepsResult.written, reason: '$result');
    }
  });
}
