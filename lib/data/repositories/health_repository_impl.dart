import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:health/health.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';

/// HealthKit and Health Connect, through `package:health` 13.3.1 (D-214).
///
/// The only file in the app that imports that package — rule 10's "behind a HealthDataSource".
/// Everything above sees [HealthRepository]; that is what makes the two platforms one code path
/// everywhere else, and what lets every test above this line run without a device.
///
/// Several choices here look arbitrary and are not. Each was checked against the installed plugin's
/// source, and `docs/HEALTH-SYNC-TRACKER.md` §4 keeps the reasons.
class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl({Health? health, SecureStore? store, bool? isIOS})
    : _health = health ?? Health(),
      _store = store ?? SecureStore(),
      _isIOS = isIOS ?? Platform.isIOS;

  /// One instance for the app's life, configured once. The plugin builds throwaway instances of
  /// its own internally, and those never learn the device id.
  final Health _health;
  final SecureStore _store;
  final bool _isIOS;

  /// Seconds per bucket. The server's diary days are exactly this long — IST has no daylight
  /// saving — so buckets anchored at the first window's start line up with every window after it.
  static final _bucketSeconds = const Duration(days: 1).inSeconds;

  /// The platform's name for each metric. **Per platform, and it has to be**: the plugin refuses a
  /// type the platform does not have, and distance is spelt differently on each.
  static HealthDataType typeFor(HealthMetric metric, {required bool isIOS}) => switch (metric) {
    HealthMetric.steps => HealthDataType.STEPS,
    HealthMetric.activeEnergy => HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthMetric.distance =>
      isIOS ? HealthDataType.DISTANCE_WALKING_RUNNING : HealthDataType.DISTANCE_DELTA,
  };

  List<HealthDataType> get _types => [
    for (final metric in HealthMetric.values) typeFor(metric, isIOS: _isIOS),
  ];

  /// Read, and only read. Asking for write access is how a permission sheet starts looking
  /// alarming, and the app never writes.
  List<HealthDataAccess> get _readOnly => [for (final _ in _types) HealthDataAccess.READ];

  var _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  // Every plugin call below is wrapped, not just the read: on Android the plugin checks for Health
  // Connect at the top of nearly every method and THROWS when it is missing.

  @override
  Future<HealthAvailability> availability() async {
    if (_isIOS) return HealthAvailability.ready;
    if (!Platform.isAndroid) return HealthAvailability.unsupported;

    try {
      await _ensureConfigured();
      return switch (await _health.getHealthConnectSdkStatus()) {
        HealthConnectSdkStatus.sdkAvailable => HealthAvailability.ready,
        // Missing or out of date. Either way the Play Store fixes it.
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          HealthAvailability.needsInstall,
        // Too old an Android to run Health Connect at all.
        _ => HealthAvailability.unsupported,
      };
    } on Object {
      return HealthAvailability.unsupported;
    }
  }

  @override
  Future<HealthPermission> permission() async {
    // HealthKit answers null for every read grant, by design. Remembering the Connect tap is the
    // only signal there is — and `null ?? false` here once meant iOS never synced at all.
    if (_isIOS) {
      return await _store.readHealthConnected()
          ? HealthPermission.unknown
          : HealthPermission.denied;
    }

    try {
      await _ensureConfigured();
      // One type at a time. Health Connect lets someone untick distance and keep steps, and a
      // single all-or-nothing check would turn that into "no sync at all".
      for (final type in _types) {
        final granted = await _health.hasPermissions([type], permissions: [HealthDataAccess.READ]);
        if (granted ?? false) return HealthPermission.granted;
      }
      return HealthPermission.denied;
    } on Object {
      return HealthPermission.denied;
    }
  }

  @override
  Future<HealthPermission> requestPermission() async {
    try {
      await _ensureConfigured();
      // On iOS this is true when the sheet was SHOWN, not when anything was granted.
      final shown = await _health.requestAuthorization(_types, permissions: _readOnly);
      if (_isIOS) {
        if (!shown) return HealthPermission.denied;
        await _store.markHealthConnected();
        return HealthPermission.unknown;
      }
      return await permission();
    } on Object {
      return HealthPermission.denied;
    }
  }

  @override
  Future<Either<Failure, Map<String, Map<HealthMetric, num>>>> readDaily(
    List<DiaryWindow> windows,
  ) async {
    if (windows.isEmpty) return const Right({});

    try {
      await _ensureConfigured();
    } on Object {
      return const Left(UnexpectedFailure('Could not read activity from this phone.'));
    }

    final totals = <String, Map<HealthMetric, num>>{};
    var failures = 0;

    for (final metric in HealthMetric.values) {
      final List<HealthDataPoint> buckets;
      try {
        // The interval query, never `getTotalStepsInInterval`: that one answers 0 for "no
        // samples", so it cannot tell an idle day from an unmeasured one. And never
        // `getHealthAggregateDataFromTypes`, which is broken on both platforms in 13.3.1.
        // Both platforms de-duplicate here, so a phone and a watch do not double a walk.
        buckets = await _health.getHealthIntervalDataFromTypes(
          startDate: windows.first.start,
          endDate: windows.last.end,
          types: [typeFor(metric, isIOS: _isIOS)],
          interval: _bucketSeconds,
        );
      } on Object {
        // One refused type must not cost the others.
        failures++;
        continue;
      }

      for (final bucket in buckets) {
        final value = bucket.value;
        if (value is! NumericHealthValue) continue;
        if (_isEmptyBucket(bucket)) continue;

        final window = windows.where((w) => w.contains(bucket.dateFrom)).firstOrNull;
        if (window == null) continue;

        (totals[window.diaryDate] ??= {})[metric] = value.numericValue;
      }
    }

    if (failures == HealthMetric.values.length) {
      // Revoked mid-read, Health Connect updating, an OEM's own failure. There is nothing for a
      // user to do about it and nothing they asked for, so the caller keeps it off the screen.
      return const Left(UnexpectedFailure('Could not read activity from this phone.'));
    }
    return Right(totals);
  }

  /// A bucket that nothing was recorded in. iOS already leaves those out; Android sends them with
  /// a value of 0, which would read as "did not move". What gives it away is that no app
  /// contributed to it — a real reading, even a real zero, always has an origin.
  bool _isEmptyBucket(HealthDataPoint bucket) => !_isIOS && bucket.sourceName.isEmpty;

  @override
  Future<bool> wasOffered() => _store.readHealthOffered();

  @override
  Future<void> markOffered() => _store.markHealthOffered();

  @override
  Future<void> openInstall() async {
    if (_isIOS) return;
    try {
      await _health.installHealthConnect();
    } on Object {
      // A Play Store link that would not open. The screen still offers it, and still says
      // manual entry works — there is nothing more useful to do with the error.
    }
  }
}
