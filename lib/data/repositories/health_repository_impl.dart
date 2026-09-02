import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:health/health.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';

/// **The Android path, and NOT WIRED YET (D-99).** iOS uses `PedometerRepositoryImpl` — CMPedometer
/// over a channel we own — because Core Motion answers "steps between two instants" directly and
/// costs no HealthKit entitlement. This file stays because Android is the opposite case: its
/// `TYPE_STEP_COUNTER` keeps no history, so Health Connect is the only thing that can fill a day
/// the app did not witness. It becomes live when the Play declaration clears (D-97).
///
/// The only file in the app that imports `package:health` (rule 10's "behind a HealthDataSource").
///
/// Everything above this sees [HealthRepository]: a step count, a permission, an availability.
/// That is what makes the two platforms one code path everywhere else, and what lets every test
/// above this line run without a device.
class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl({Health? health}) : _health = health ?? Health();

  final Health _health;

  /// Read access to a step count, and nothing else. The app never writes to the health store, and
  /// asking for more than it uses is how a permission sheet starts looking alarming.
  static const _types = [HealthDataType.STEPS];
  static const _access = [HealthDataAccess.READ];

  var _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<HealthAvailability> availability() async {
    await _ensureConfigured();

    if (Platform.isIOS) return HealthAvailability.ready;
    if (!Platform.isAndroid) return HealthAvailability.unsupported;

    // Android 14+ has Health Connect in the OS; 8–13 needs the Play Store app, which the user can
    // be sent to install rather than being told their phone cannot do it.
    return await _health.isHealthConnectAvailable()
        ? HealthAvailability.ready
        : HealthAvailability.needsInstall;
  }

  @override
  Future<bool> hasStepPermission() async {
    await _ensureConfigured();
    // Null means "cannot tell" on iOS: HealthKit deliberately does not reveal whether READ access
    // was granted, because that itself would leak whether the user has the data. Treated as not
    // granted, so the app asks — and HealthKit silently no-ops if it already has it.
    return await _health.hasPermissions(_types, permissions: _access) ?? false;
  }

  @override
  Future<bool> requestStepPermission() async {
    await _ensureConfigured();
    return _health.requestAuthorization(_types, permissions: _access);
  }

  @override
  Future<Either<Failure, int?>> stepsBetween(DateTime start, DateTime end) async {
    try {
      await _ensureConfigured();
      // The platform's own aggregate, not a sum of samples: an iPhone and a Watch both record the
      // same walk, and adding them up would double a user's day.
      return Right(await _health.getTotalStepsInInterval(start, end));
    } on Object {
      // Anything the platform throws — revoked mid-read, Health Connect updating, an OEM's own
      // failure. There is nothing for a user to do and nothing they asked for, so it is a Failure
      // the caller swallows rather than copy anyone reads (see StepSync).
      return const Left(UnexpectedFailure('Could not read steps from this phone.'));
    }
  }
}
