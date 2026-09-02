import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';

/// Read-only access to the phone's own health store. CLAUDE.md rule 10.
///
/// HealthKit on iOS, Health Connect on Android, and **never Google Fit** — its APIs shut down at
/// the end of 2026. The interface names neither, because the layer above must not care: the app
/// asks "how many steps between these two instants" and gets a number or a reason it cannot have
/// one.
///
/// Nothing here writes. The app reads a step count and stores it as a measurement of its own; it
/// never puts anything back into the user's health record.
abstract class HealthRepository {
  /// Whether this phone can answer at all, before any permission is involved.
  Future<HealthAvailability> availability();

  /// Whether the user has already granted step access. Never prompts.
  Future<bool> hasStepPermission();

  /// Prompts. Returns whether access was granted.
  ///
  /// A denial is a normal answer, not a failure: manual entry is always available (rule 10), so
  /// nothing about this flow is allowed to become a dead end.
  Future<bool> requestStepPermission();

  /// Steps in `[start, end)`, both supplied by the SERVER as the diary day's window (D-98).
  ///
  /// Null means the platform has no answer — which is different from zero, and the caller must not
  /// store it as one.
  Future<Either<Failure, int?>> stepsBetween(DateTime start, DateTime end);
}

/// Why a phone might not be able to report steps, before permissions are even asked.
enum HealthAvailability {
  ready,

  /// Health Connect is a separate app on Android 8–13 and may not be installed. The user can be
  /// sent to install it, so this is a prompt rather than a dead end.
  needsInstall,

  /// No health store on this platform or OS version. Manual entry only, and the UI should not
  /// offer to connect anything.
  unsupported,
}
