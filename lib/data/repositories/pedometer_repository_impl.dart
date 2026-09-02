import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';

/// Steps from the phone's own motion coprocessor, over a channel we own (D-99).
///
/// CMPedometer on iOS, via `ios/Runner/StepCounter.swift`. Chosen over HealthKit and over both
/// pedometer plugins on pub.dev:
///
/// * HealthKit wants an entitlement and draws health-app scrutiny in App Review, to answer a
///   question Core Motion answers directly.
/// * `pedometer` (carp-dk) is the better-maintained package but streams only "steps since boot".
///   A diary day needs the count between two instants, and a stream cannot say what the counter
///   read at 04:00 if the app was not running then — someone opening the app at 6 p.m. would be
///   shown a few hundred steps for a full day, confidently.
/// * `cm_pedometer` has the right call but was last published 21 months ago, and its README asks
///   for a `processing` background mode this app does not need.
///
/// The channel is about eighty lines of Swift. That is smaller than the risk of either.
///
/// **There is no `Platform.isIOS` check.** The channel only exists in the iOS host, so Android
/// raises `MissingPluginException` and every method already degrades to "unsupported" or "no
/// answer" — which is the behaviour a platform check would have hand-written, using a second
/// mechanism that no test could reach (`Platform.isIOS` is false in the test VM, so the checks
/// were the only thing the suite ever exercised). Android's `TYPE_STEP_COUNTER` keeps no history
/// and cannot answer this interface's question anyway; Health Connect is the Android answer and
/// comes later.
class PedometerRepositoryImpl implements HealthRepository {
  PedometerRepositoryImpl({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'app.eatzify/step_counter';

  final MethodChannel _channel;

  @override
  Future<HealthAvailability> availability() async {
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      return available ?? false ? HealthAvailability.ready : HealthAvailability.unsupported;
    } on PlatformException {
      return HealthAvailability.unsupported;
    } on MissingPluginException {
      // The channel is not registered — an older build of the host app. Not a crash: the app is
      // fully usable without a step count.
      return HealthAvailability.unsupported;
    }
  }

  @override
  Future<bool> hasStepPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> requestStepPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<Either<Failure, int?>> stepsBetween(DateTime start, DateTime end) async {
    try {
      // Milliseconds since epoch, UTC. The window came from the server and is passed through
      // untouched — no local date arithmetic anywhere on this path (rule 8, D-98).
      final steps = await _channel.invokeMethod<int>('stepsBetween', {
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
      });
      // Null is "no answer" — denied, or older than the seven days CMPedometer keeps. The caller
      // must not store it as zero.
      return Right(steps);
    } on PlatformException {
      return const Left(UnexpectedFailure('Could not read steps from this phone.'));
    } on MissingPluginException {
      return const Right(null);
    }
  }
}
