import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/health_metric.dart';

/// Read-only access to the phone's own health store. CLAUDE.md rule 10.
///
/// HealthKit on iOS, Health Connect on Android, and **never Google Fit** — its APIs shut down at
/// the end of 2026. The interface names neither, because the layer above must not care: the app
/// asks "what did this phone record in these windows" and gets numbers or a reason it cannot.
///
/// Nothing here writes. The app reads and stores the result as a measurement of its own; it never
/// puts anything back into the user's health record.
abstract class HealthRepository {
  /// Whether this phone can answer at all, before any permission is involved.
  Future<HealthAvailability> availability();

  /// What the app may read, as far as it can tell. Never prompts.
  Future<HealthPermission> permission();

  /// Prompts, and answers with where that left things.
  ///
  /// A refusal is a normal answer, not a failure: manual entry is always available (rule 10), so
  /// nothing about this flow is allowed to become a dead end.
  Future<HealthPermission> requestPermission();

  /// Each [HealthMetric]'s total per window, keyed by diary date. The windows come from the SERVER
  /// (rule 8).
  ///
  /// **A metric with nothing recorded in a window is ABSENT from that window's map — never zero.**
  /// "Nobody measured" and "they did not move" are different sentences, and only one is ever true.
  Future<Either<Failure, Map<String, Map<HealthMetric, num>>>> readDaily(List<DiaryWindow> windows);

  /// Sends the user to install or update Health Connect. Android 8–13 only; a no-op elsewhere.
  Future<void> openInstall();

  /// Whether this account has already been offered a connect, unprompted (D-218). The offer comes
  /// once; after that it waits on Home for a tap.
  Future<bool> wasOffered();

  Future<void> markOffered();
}

/// Why a phone might not be able to report anything, before permissions are even asked.
enum HealthAvailability {
  ready,

  /// Health Connect is a separate app on Android 9–13 and may be missing or out of date. The user
  /// can be sent to fix that, so this is a prompt rather than a dead end.
  needsInstall,

  /// No health store on this platform or OS version. Manual entry only, and the UI should not
  /// offer to connect anything.
  unsupported,
}
