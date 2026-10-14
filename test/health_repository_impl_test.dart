import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/data/repositories/health_repository_impl.dart';
import 'package:health_pro/domain/entities/health_metric.dart';

import 'fakes.dart';

/// D-214 / D-215. The platform adapter, against a stand-in for the plugin.
///
/// Two behaviours here broke silently before and would again: iOS permission, which HealthKit will
/// not report, and "nothing recorded", which the plugin reports as a zero on Android.

/// Stands in for `package:health` by overriding exactly the calls the adapter makes.
class _PluginDouble extends Health {
  bool sheetShown = true;
  Error? requestThrows;

  /// Per requested type: the buckets to answer with, or an error to throw.
  final answers = <HealthDataType, Object>{};
  final asked = <({HealthDataType type, DateTime start, DateTime end, int interval})>[];

  @override
  Future<void> configure() async {}

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    if (requestThrows != null) throw requestThrows!;
    return sheetShown;
  }

  @override
  Future<List<HealthDataPoint>> getHealthIntervalDataFromTypes({
    required DateTime startDate,
    required DateTime endDate,
    required List<HealthDataType> types,
    required int interval,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    final type = types.single;
    asked.add((type: type, start: startDate, end: endDate, interval: interval));
    final answer = answers[type] ?? const <HealthDataPoint>[];
    if (answer is List<HealthDataPoint>) return answer;
    throw answer as Error;
  }

  /// Sleep's session read: every requested type's points, or the first error among them.
  final sleepAsked = <({List<HealthDataType> types, DateTime start, DateTime end})>[];

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    sleepAsked.add((types: types, start: startTime, end: endTime));
    final points = <HealthDataPoint>[];
    for (final type in types) {
      final answer = answers[type] ?? const <HealthDataPoint>[];
      if (answer is! List<HealthDataPoint>) throw answer as Error;
      points.addAll(answer);
    }
    return points;
  }
}

/// One night (or one stage of it), ending at [end], as the plugin reports sleep: minutes.
HealthDataPoint sleepPoint(HealthDataType type, DateTime end, num minutes) => HealthDataPoint(
  uuid: '',
  value: NumericHealthValue(numericValue: minutes),
  type: type,
  unit: HealthDataUnit.MINUTE,
  dateFrom: end.subtract(Duration(minutes: minutes.toInt())),
  dateTo: end,
  sourcePlatform: HealthPlatformType.googleHealthConnect,
  sourceDeviceId: '',
  sourceId: '',
  sourceName: 'app',
);

final _d1 = DiaryWindow(
  diaryDate: '2026-09-16',
  start: DateTime.utc(2026, 9, 15, 22, 30),
  end: DateTime.utc(2026, 9, 16, 22, 30),
);
final _d2 = DiaryWindow(
  diaryDate: '2026-09-17',
  start: DateTime.utc(2026, 9, 16, 22, 30),
  end: DateTime.utc(2026, 9, 17, 22, 30),
);

/// One day's total, the shape the plugin returns from an interval query.
HealthDataPoint bucket(HealthDataType type, DiaryWindow day, num value, {String source = 'app'}) =>
    HealthDataPoint(
      uuid: '',
      value: NumericHealthValue(numericValue: value),
      type: type,
      unit: HealthDataUnit.COUNT,
      dateFrom: day.start,
      dateTo: day.end,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      sourceDeviceId: '',
      sourceId: '',
      sourceName: source,
    );

void main() {
  late _PluginDouble plugin;
  late SecureStore store;

  setUp(() {
    plugin = _PluginDouble();
    store = SecureStore(storage: FakeSecureStorage());
  });

  HealthRepositoryImpl ios() => HealthRepositoryImpl(health: plugin, store: store, isIOS: true);
  HealthRepositoryImpl android() =>
      HealthRepositoryImpl(health: plugin, store: store, isIOS: false);

  group('iOS permission', () {
    test('should say denied before anyone has connected', () async {
      expect(await ios().permission(), HealthPermission.denied);
    });

    /// The bug this guards: `hasPermissions(...) ?? false` is always false on iOS, because HealthKit
    /// answers null for every read grant — and sync never ran on an iPhone.
    test('should say unknown, not denied, once the user has connected', () async {
      expect(await ios().requestPermission(), HealthPermission.unknown);
      expect(
        await ios().permission(),
        HealthPermission.unknown,
        reason: 'remembered across instances',
      );
    });

    test('should not remember a connect whose sheet never appeared', () async {
      plugin.sheetShown = false;
      expect(await ios().requestPermission(), HealthPermission.denied);
      expect(await ios().permission(), HealthPermission.denied);
    });

    test('should treat a plugin error as not connected rather than crash', () async {
      plugin.requestThrows = StateError('HealthKit unavailable');
      expect(await ios().requestPermission(), HealthPermission.denied);
    });

    /// It belongs to the account. The next person to sign in on this phone connects for themselves.
    test('should forget the connection on sign-out', () async {
      await ios().requestPermission();
      await store.clear();
      expect(await ios().permission(), HealthPermission.denied);
    });
  });

  /// D-218. The unprompted connect sheet comes once per account, not once per launch.
  test('should remember the one-time offer until sign-out', () async {
    expect(await ios().wasOffered(), isFalse);
    await ios().markOffered();
    expect(await android().wasOffered(), isTrue, reason: 'one flag, whichever instance reads it');
    await store.clear();
    expect(await ios().wasOffered(), isFalse);
  });

  group('reading', () {
    test('should ask for one-day buckets across all the windows at once', () async {
      await ios().readDaily([_d1, _d2]);

      // Sleep is sessions, read separately; every other metric is one bucketed query.
      expect(plugin.asked, hasLength(HealthMetric.values.length - 1));
      for (final call in plugin.asked) {
        expect(call.start, _d1.start);
        expect(call.end, _d2.end);
        expect(call.interval, const Duration(days: 1).inSeconds);
      }
    });

    test('should ask each platform for distance by its own name', () async {
      await ios().readDaily([_d1]);
      expect(plugin.asked.map((c) => c.type), contains(HealthDataType.DISTANCE_WALKING_RUNNING));

      plugin.asked.clear();
      await android().readDaily([_d1]);
      expect(plugin.asked.map((c) => c.type), contains(HealthDataType.DISTANCE_DELTA));
    });

    test('should file each bucket under the window it starts in', () async {
      plugin.answers[HealthDataType.STEPS] = [
        bucket(HealthDataType.STEPS, _d1, 4000),
        bucket(HealthDataType.STEPS, _d2, 9000),
      ];
      plugin.answers[HealthDataType.ACTIVE_ENERGY_BURNED] = [
        bucket(HealthDataType.ACTIVE_ENERGY_BURNED, _d2, 310),
      ];

      final read = await ios().readDaily([_d1, _d2]);
      expect(read.getOrElse(() => {}), {
        '2026-09-16': {HealthMetric.steps: 4000},
        '2026-09-17': {HealthMetric.steps: 9000, HealthMetric.activeEnergy: 310},
      });
    });

    test('should leave a metric absent when the platform returned no bucket', () async {
      final read = await ios().readDaily([_d1]);
      expect(read.getOrElse(() => {'x': {}}), isEmpty, reason: 'absent, not zero');
    });

    /// Android sends a bucket for a day nothing was recorded on, valued 0. No app contributed to it,
    /// and that is what tells it apart from a real idle day.
    test('should drop an Android bucket nothing contributed to', () async {
      plugin.answers[HealthDataType.STEPS] = [
        bucket(HealthDataType.STEPS, _d1, 0, source: ''),
        bucket(HealthDataType.STEPS, _d2, 0, source: 'com.google.android.apps.fitness'),
      ];

      final read = await android().readDaily([_d1, _d2]);
      expect(read.getOrElse(() => {}), {
        '2026-09-17': {HealthMetric.steps: 0},
      }, reason: 'the 17th is a real zero; the 16th was never measured');
    });

    test('should not apply that rule on iOS, which names no source on a total', () async {
      plugin.answers[HealthDataType.STEPS] = [bucket(HealthDataType.STEPS, _d1, 5000, source: '')];
      final read = await ios().readDaily([_d1]);
      expect(read.getOrElse(() => {}), {
        '2026-09-16': {HealthMetric.steps: 5000},
      });
    });

    /// Health Connect lets someone untick distance and keep steps.
    test('should keep the metrics it can read when one is refused', () async {
      plugin.answers[HealthDataType.STEPS] = [bucket(HealthDataType.STEPS, _d1, 6000)];
      plugin.answers[HealthDataType.DISTANCE_DELTA] = StateError('SecurityException');

      final read = await android().readDaily([_d1]);
      expect(read.isRight(), isTrue);
      expect(read.getOrElse(() => {}), {
        '2026-09-16': {HealthMetric.steps: 6000},
      });
    });

    test('should fail when nothing at all could be read', () async {
      for (final metric in HealthMetric.values) {
        plugin.answers[HealthRepositoryImpl.typeFor(metric, isIOS: false)] = StateError('gone');
      }
      expect((await android().readDaily([_d1])).isLeft(), isTrue);
    });

    test('should file a night under the morning it ended in', () async {
      // Ends 01:30 UTC on the 16th — 07:00 IST — inside the 16th's window.
      plugin.answers[HealthDataType.SLEEP_SESSION] = [
        sleepPoint(HealthDataType.SLEEP_SESSION, DateTime.utc(2026, 9, 16, 1, 30), 450),
      ];

      final read = await android().readDaily([_d1, _d2]);

      expect(read.getOrElse(() => {}), {
        '2026-09-16': {HealthMetric.sleep: 450},
      });
      // A night ending in the first window began the evening before it.
      expect(plugin.sleepAsked.single.start, _d1.start.subtract(const Duration(days: 1)));
    });

    test('should add up an Apple Watch night told in stages', () async {
      final morning = DateTime.utc(2026, 9, 16, 1, 30);
      plugin
        ..answers[HealthDataType.SLEEP_LIGHT] = [
          sleepPoint(HealthDataType.SLEEP_LIGHT, morning, 240),
        ]
        ..answers[HealthDataType.SLEEP_DEEP] = [sleepPoint(HealthDataType.SLEEP_DEEP, morning, 90)]
        ..answers[HealthDataType.SLEEP_REM] = [sleepPoint(HealthDataType.SLEEP_REM, morning, 100)];

      final read = await ios().readDaily([_d1]);

      expect(read.getOrElse(() => {}), {
        '2026-09-16': {HealthMetric.sleep: 430},
      });
    });

    test('should leave sleep absent, not zero, when no night was recorded', () async {
      final read = await android().readDaily([_d1]);
      expect(read.getOrElse(() => {'x': {}}), isEmpty);
    });

    test('should keep the other metrics when sleep is refused', () async {
      plugin.answers[HealthDataType.STEPS] = [bucket(HealthDataType.STEPS, _d1, 6000)];
      plugin.answers[HealthDataType.SLEEP_SESSION] = StateError('SecurityException');

      final read = await android().readDaily([_d1]);

      expect(read.getOrElse(() => {}), {
        '2026-09-16': {HealthMetric.steps: 6000},
      });
    });

    test('should not ask the platform about no windows at all', () async {
      final read = await ios().readDaily(const []);
      expect(read.isRight(), isTrue);
      expect(plugin.asked, isEmpty);
    });
  });
}
