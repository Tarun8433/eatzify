import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';

import '../fakes.dart';

/// D-214 / D-215. Every rule about WHEN a sync may write lives in `SyncHealth`, so it can be tested
/// without a phone — which is the only way it can be tested at all. The platform calls themselves
/// sit behind `HealthRepository` and need a device; everything that decides what to send is here.

const _today = '2026-09-17';

/// 04:00 IST on the 17th, as the server sends it. The test never works this out; it is a fixture.
final _todayStart = DateTime.utc(2026, 9, 16, 22, 30);
final _todayEnd = DateTime.utc(2026, 9, 17, 22, 30);

class _FakeHealth implements HealthRepository {
  // Mutable fields rather than constructor arguments: each test changes the one condition it is
  // about, which reads as "given permission is refused" instead of a row of defaults restated.
  HealthAvailability available = HealthAvailability.ready;
  HealthPermission permitted = HealthPermission.granted;

  /// What the phone recorded, per diary date. Absent keys are days or metrics with no samples.
  Either<Failure, Map<String, Map<HealthMetric, num>>> recorded = const Right({
    _today: {HealthMetric.steps: 9500, HealthMetric.activeEnergy: 320, HealthMetric.distance: 6100},
  });

  int reads = 0;
  int prompts = 0;
  List<DiaryWindow>? askedAbout;

  @override
  Future<HealthAvailability> availability() async => available;

  @override
  Future<HealthPermission> permission() async => permitted;

  /// What a prompt leaves things at. Null keeps whatever [permitted] already says.
  HealthPermission? afterPrompt;

  @override
  Future<HealthPermission> requestPermission() async {
    prompts++;
    return permitted = afterPrompt ?? permitted;
  }

  @override
  Future<Either<Failure, Map<String, Map<HealthMetric, num>>>> readDaily(
    List<DiaryWindow> windows,
  ) async {
    reads++;
    askedAbout = windows;
    return recorded;
  }

  @override
  Future<void> openInstall() async {}

  @override
  Future<bool> wasOffered() async => false;

  @override
  Future<void> markOffered() async {}
}

/// A day as the server sends it: the window is the server's, never the client's (rule 8).
DiaryDay dayWith({
  int? steps,
  int? added,
  MeasurementSource source = MeasurementSource.manual,
  int? burned,
  bool window = true,
}) => DiaryDay(
  diaryDate: _today,
  entries: const [],
  totals: const Macros(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
  steps: steps,
  stepsAdded: added,
  stepsSource: source,
  energyBurnedKcal: burned,
  windowStart: window ? _todayStart : null,
  windowEnd: window ? _todayEnd : null,
);

void main() {
  late _FakeHealth health;
  late FakeMeasurementsRepository measurements;
  late FakeDiaryRepository diary;
  late SyncHealth sync;

  setUp(() {
    health = _FakeHealth();
    measurements = FakeMeasurementsRepository();
    diary = FakeDiaryRepository();
    sync = SyncHealth(health: health, measurements: measurements, diary: diary);
  });

  List<NewMeasurement> sent() => measurements.batches.expand((b) => b).toList();
  Map<String, double> sentByKind() => {for (final r in sent()) r.kind: r.value};

  group('today', () {
    test('should send all three figures in one request when nothing is recorded yet', () async {
      expect(await sync(dayWith()), SyncHealthResult.written);

      expect(measurements.batches, hasLength(1), reason: 'one request, not one per metric');
      expect(sentByKind(), {'steps': 9500, 'energy_burned_kcal': 320, 'distance_m': 6100});
    });

    test('should send each figure in the unit the server expects for its kind', () async {
      await sync(dayWith());
      expect(
        {for (final r in sent()) r.kind: r.unit},
        {'steps': 'steps', 'energy_burned_kcal': 'kcal', 'distance_m': 'm'},
      );
    });

    test('should label every figure as a device reading, not a person', () async {
      await sync(dayWith());
      expect(sent().every((r) => r.source.isAutomatic), isTrue);
    });

    /// The server turns this instant back into the diary day. Sending the window's own start means
    /// the phone never had to know where the day begins.
    test('should date each reading at the start of the window the server sent', () async {
      await sync(dayWith());
      expect(sent().every((r) => r.at == _todayStart), isTrue);
      expect(health.askedAbout?.single.start, _todayStart);
      expect(health.askedAbout?.single.end, _todayEnd);
    });

    test('should send whole units rather than platform noise', () async {
      health.recorded = const Right({
        _today: {HealthMetric.distance: 6100.46, HealthMetric.activeEnergy: 319.7},
      });
      await sync(dayWith());
      expect(sentByKind(), {'distance_m': 6100, 'energy_burned_kcal': 320});
    });

    test('should not guess the diary day when the server did not send one', () async {
      expect(await sync(dayWith(window: false)), SyncHealthResult.noWindow);
      expect(health.reads, 0, reason: 'rule 8: the 04:00 IST boundary lives in one place');
    });
  });

  group('absent is not zero', () {
    test('should write nothing when the phone recorded nothing', () async {
      health.recorded = const Right({});

      expect(await sync(dayWith()), SyncHealthResult.nothingToWrite);
      expect(
        measurements.batches,
        isEmpty,
        reason: 'storing 0 would say "you did not move", which is a different claim',
      );
    });

    test('should leave out a metric the phone has no samples for', () async {
      health.recorded = const Right({
        _today: {HealthMetric.steps: 4200},
      });

      await sync(dayWith());
      expect(sentByKind(), {'steps': 4200}, reason: 'no distance and no energy were measured');
    });

    test('should store a genuine zero, which is not the same thing', () async {
      health.recorded = const Right({
        _today: {HealthMetric.steps: 0},
      });

      expect(
        await sync(dayWith(steps: 500, source: MeasurementSource.appleHealth)),
        SyncHealthResult.written,
      );
      expect(sentByKind(), {'steps': 0});
    });
  });

  group('permission', () {
    test('should never prompt on its own', () async {
      health.permitted = HealthPermission.denied;

      expect(await sync(dayWith()), SyncHealthResult.notPermitted);
      expect(health.prompts, 0, reason: 'a permission sheet follows a tap, not an app launch');
      expect(health.reads, 0);
    });

    /// The iOS case. HealthKit never says whether read access was granted, and treating "cannot
    /// tell" as "no" switched sync off on every iPhone.
    test('should still read when the platform cannot say whether it is allowed', () async {
      health.permitted = HealthPermission.unknown;

      expect(await sync(dayWith()), SyncHealthResult.written);
      expect(health.reads, 1);
    });

    test('should skip a phone with no health store', () async {
      health.available = HealthAvailability.unsupported;
      expect(await sync(dayWith()), SyncHealthResult.unavailable);
      expect(health.reads, 0);
    });

    test('should skip a phone that still needs Health Connect installed', () async {
      health.available = HealthAvailability.needsInstall;
      expect(await sync(dayWith()), SyncHealthResult.unavailable);
    });
  });

  group('what is already there', () {
    /// D-97. A correction someone typed outranks the phone for the rest of the day.
    test('should leave a hand-typed step count alone and still send the rest', () async {
      await sync(dayWith(steps: 8000));

      expect(sentByKind().containsKey('steps'), isFalse);
      expect(sentByKind(), {'energy_burned_kcal': 320, 'distance_m': 6100});
    });

    /// D-221. Steps someone added sit on top of the phone's count, so the phone keeps counting.
    test('should keep refreshing the phone’s count under steps someone added', () async {
      await sync(dayWith(steps: 4500, added: 500, source: MeasurementSource.appleHealth));
      expect(sentByKind()['steps'], 9500);
    });

    test('should count a day that only has added steps as having no phone count yet', () async {
      await sync(dayWith(steps: 500, added: 500));
      expect(sentByKind()['steps'], 9500);
    });

    test('should compare the phone’s count without the added steps', () async {
      await sync(
        dayWith(steps: 10000, added: 500, source: MeasurementSource.appleHealth, burned: 320),
      );
      expect(sentByKind().containsKey('steps'), isFalse, reason: '9,500 is already there');
    });

    test('should refresh a step count the phone itself wrote earlier', () async {
      await sync(dayWith(steps: 4000, source: MeasurementSource.healthConnect));
      expect(sentByKind()['steps'], 9500, reason: 'a step count grows through the day');
    });

    test('should not resend figures the day already shows', () async {
      await sync(dayWith(steps: 9500, source: MeasurementSource.appleHealth, burned: 320));
      expect(sentByKind(), {'distance_m': 6100}, reason: 'the day carries no distance to compare');
    });

    test('should report nothing to do when every figure is already there', () async {
      health.recorded = const Right({
        _today: {HealthMetric.steps: 9500, HealthMetric.activeEnergy: 320},
      });

      expect(
        await sync(dayWith(steps: 9500, source: MeasurementSource.appleHealth, burned: 320)),
        SyncHealthResult.unchanged,
      );
      expect(measurements.batches, isEmpty);
    });

    /// A write makes Home reload, and the reload syncs again. Without a memory of what was sent,
    /// distance — which the day never carries — would be sent on every reload, forever.
    test('should not send the same figures twice, so a reload cannot loop', () async {
      expect(await sync(dayWith()), SyncHealthResult.written);
      final reloaded = dayWith(steps: 9500, source: MeasurementSource.appleHealth, burned: 320);

      expect(await sync(reloaded), SyncHealthResult.unchanged);
      expect(measurements.batches, hasLength(1));
    });

    test('should send a figure again once it has changed', () async {
      await sync(dayWith());
      health.recorded = const Right({
        _today: {HealthMetric.distance: 7400},
      });

      expect(await sync(dayWith()), SyncHealthResult.written);
      expect(measurements.batches.last.single.value, 7400);
    });
  });

  group('failures stay quiet', () {
    test('should report a failed read without writing', () async {
      health.recorded = const Left(UnexpectedFailure('boom'));
      expect(await sync(dayWith()), SyncHealthResult.readFailed);
      expect(measurements.batches, isEmpty);
    });

    /// If a failed write were remembered as sent, the figure would never be retried.
    test('should retry a write that failed', () async {
      final failing = FakeMeasurementsRepository(failure: const OfflineFailure('offline'));
      final flaky = SyncHealth(health: health, measurements: failing, diary: diary);

      expect(await flaky(dayWith()), SyncHealthResult.sendFailed);
      expect(await flaky(dayWith()), SyncHealthResult.sendFailed);
      expect(failing.batches, hasLength(2), reason: 'the second attempt was not skipped');
    });

    test('should ask Home to reload only after a write', () async {
      for (final result in SyncHealthResult.values) {
        expect(result.changedTheDay, result == SyncHealthResult.written, reason: '$result');
      }
    });
  });

  group('a tapped sync', () {
    List<DiaryWindow> windows(int count) => [
      for (var i = 0; i < count; i++)
        DiaryWindow(
          diaryDate: 'day-$i',
          start: _todayStart.add(Duration(days: i - count + 1)),
          end: _todayEnd.add(Duration(days: i - count + 1)),
        ),
    ];

    test('should ask the server for the windows, never work them out', () async {
      diary.windowsResult = windows(SyncHealth.backfillDays);
      health.recorded = const Right({});

      await sync.syncNow();
      expect(health.askedAbout, hasLength(SyncHealth.backfillDays));
      expect(health.askedAbout?.first.diaryDate, 'day-0');
    });

    test('should send every day in one request, each dated inside its own window', () async {
      final days = windows(3);
      diary.windowsResult = days;
      health.recorded = const Right({
        'day-0': {HealthMetric.steps: 3000},
        'day-2': {HealthMetric.steps: 7000, HealthMetric.distance: 5000},
      });

      expect(await sync.syncNow(), SyncHealthResult.written);
      expect(measurements.batches, hasLength(1));
      expect(
        [for (final r in sent()) (r.kind, r.value, r.at)],
        [
          ('steps', 3000, days[0].start),
          ('steps', 7000, days[2].start),
          ('distance_m', 5000, days[2].start),
        ],
        reason: 'day-1 recorded nothing, so nothing is sent for it',
      );
    });

    /// Every backfill send fits the server's 200-reading cap.
    test('should stay under the bulk limit for a full month', () async {
      diary.windowsResult = windows(SyncHealth.backfillDays);
      health.recorded = Right({
        for (var i = 0; i < SyncHealth.backfillDays; i++)
          'day-$i': {for (final m in HealthMetric.values) m: 1000 + i},
      });

      await sync.syncNow();
      expect(sent().length, SyncHealth.backfillDays * HealthMetric.values.length);
      expect(sent().length, lessThanOrEqualTo(200));
    });

    test('should say the server was unreachable when it cannot give the windows', () async {
      diary.windowsResult = null;
      expect(await sync.syncNow(), SyncHealthResult.sendFailed);
      expect(health.reads, 0);
    });

    /// The tap is what makes asking acceptable.
    test('should ask for access when it is not granted, and stop if refused', () async {
      diary.windowsResult = windows(3);
      health.permitted = HealthPermission.denied;

      expect(await sync.syncNow(), SyncHealthResult.notPermitted);
      expect(health.prompts, 1);
      expect(health.reads, 0);
    });

    test('should carry on once access is given', () async {
      diary.windowsResult = windows(1);
      health
        ..permitted = HealthPermission.denied
        ..afterPrompt = HealthPermission.granted
        ..recorded = const Right({
          'day-0': {HealthMetric.steps: 456},
        });

      expect(await sync.syncNow(), SyncHealthResult.written);
      expect(health.prompts, 1);
    });

    test('should not ask again when access is already granted', () async {
      diary.windowsResult = windows(1);
      health.recorded = const Right({});
      await sync.syncNow();
      expect(health.prompts, 0);
    });

    /// iOS never says what was granted — and after a reinstall it may have forgotten. Asking is
    /// silent once settled, so a tap always asks.
    test('should ask when the platform cannot say, which covers a reinstall on iOS', () async {
      diary.windowsResult = windows(1);
      health
        ..permitted = HealthPermission.unknown
        ..recorded = const Right({});
      await sync.syncNow();
      expect(health.prompts, 1);
    });

    /// D-218. The watch says 456, the person typed 200 this morning, and then tapped Sync.
    test('should let only today replace a typed figure', () async {
      final days = windows(2);
      diary.windowsResult = days;
      health.recorded = const Right({
        'day-0': {HealthMetric.steps: 3000},
        'day-1': {HealthMetric.steps: 456},
      });

      await sync.syncNow();
      expect(
        {for (final r in sent()) r.at: r.replaceManual},
        {days[0].start: false, days[1].start: true},
      );
    });

    /// A background sync that was refused earlier leaves a memory of having "sent" the figure. The
    /// tap must not be silenced by it.
    test('should send today again even if a background sync already tried', () async {
      await sync(dayWith(steps: 200)); // typed: the background sync skips steps
      diary.windowsResult = [DiaryWindow(diaryDate: _today, start: _todayStart, end: _todayEnd)];

      expect(await sync.syncNow(), SyncHealthResult.written);
      final tapped = measurements.batches.last;
      expect(
        {for (final r in tapped) r.kind: r.replaceManual},
        {'steps': true, 'energy_burned_kcal': true, 'distance_m': true},
      );
    });

    test('should never ask the server to replace anything on a background sync', () async {
      await sync(dayWith());
      expect(sent().every((r) => !r.replaceManual), isTrue);
    });

    test('should know which outcomes mean a phone is connected', () {
      expect(SyncHealthResult.notPermitted.isConnected, isFalse);
      expect(SyncHealthResult.unavailable.isConnected, isFalse);
      expect(SyncHealthResult.written.isConnected, isTrue);
      expect(SyncHealthResult.nothingToWrite.isConnected, isTrue);
    });
  });
}
