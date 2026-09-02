import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/repositories/pedometer_repository_impl.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';

/// D-99. The contract with `ios/Runner/StepCounter.swift`, from the Dart side.
///
/// The Swift itself needs a device. What can be checked here is the half that has historically
/// gone wrong: what is sent over the channel, and what each reply is turned into — particularly
/// that a null stays a null all the way up rather than becoming a zero someone reads as "you did
/// not move today".
///
/// The first version of this file passed nothing, which was the useful part: the repository
/// guarded every method with `Platform.isIOS`, that is false in the test VM, and so every call
/// returned before reaching the channel. The guard was also redundant — Android has no channel to
/// call, and `MissingPluginException` already produced the same answer. It is gone, and these run
/// against the channel for real.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PedometerRepositoryImpl.channelName);
  final calls = <MethodCall>[];
  late Object? reply;
  late Exception? error;

  void mockChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        if (error != null) throw error!;
        return reply;
      },
    );
  }

  setUp(() {
    calls.clear();
    reply = null;
    error = null;
    mockChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  /// Constructed with the mocked channel, so the platform guard is not what is under test.
  PedometerRepositoryImpl subject() => PedometerRepositoryImpl(channel: channel);

  group('the window is passed through, never recomputed', () {
    test('sends the exact instants it was given, in epoch milliseconds', () async {
      reply = 9500;
      // The server's diary window: 04:00 IST on 31 Aug is 22:30 UTC on the 30th (D-98).
      final start = DateTime.utc(2026, 8, 30, 22, 30);
      final end = DateTime.utc(2026, 8, 31, 22, 30);

      await subject().stepsBetween(start, end);

      expect(calls.single.method, 'stepsBetween');
      final args = calls.single.arguments as Map;
      expect(args['startMs'], start.millisecondsSinceEpoch);
      expect(args['endMs'], end.millisecondsSinceEpoch);
    });

    test('does no date arithmetic of its own (rule 8)', () async {
      reply = 1;
      final start = DateTime.utc(2026, 1, 1, 3, 17, 42, 123);
      await subject().stepsBetween(start, start.add(const Duration(days: 1)));

      final args = calls.single.arguments as Map;
      expect(
        DateTime.fromMillisecondsSinceEpoch(args['startMs'] as int, isUtc: true),
        start,
        reason: 'not rounded, not shifted, not localised',
      );
    });
  });

  group('a reply of null is not a reply of zero', () {
    test('null comes back as null', () async {
      reply = null;
      final result = await subject().stepsBetween(DateTime.utc(2026), DateTime.utc(2026, 1, 2));

      expect(
        result.fold((_) => 'failure', (steps) => steps),
        isNull,
        reason: 'denied, or older than the seven days CMPedometer keeps — not a day of no walking',
      );
    });

    test('a real zero comes back as zero', () async {
      reply = 0;
      final result = await subject().stepsBetween(DateTime.utc(2026), DateTime.utc(2026, 1, 2));
      expect(result.fold((_) => -1, (steps) => steps), 0);
    });
  });

  group('platform failures do not reach a screen', () {
    test('a PlatformException becomes a Failure, not an exception', () async {
      error = PlatformException(code: 'CMErrorMotionActivityNotAuthorized');
      final result = await subject().stepsBetween(DateTime.utc(2026), DateTime.utc(2026, 1, 2));
      expect(result.isLeft(), isTrue);
      expect(result.fold((f) => f, (_) => null), isA<UnexpectedFailure>());
    });

    test('a missing channel is "no answer", not a crash', () async {
      // An older host binary with no StepCounter registered. The app is entirely usable without a
      // step count, so this must not be an error anyone sees.
      error = MissingPluginException();
      final result = await subject().stepsBetween(DateTime.utc(2026), DateTime.utc(2026, 1, 2));
      expect(result.fold((_) => 'failure', (steps) => steps), isNull);
    });

    test('availability degrades to unsupported rather than throwing', () async {
      error = MissingPluginException();
      expect(await subject().availability(), HealthAvailability.unsupported);
    });

    test('a permission check never throws', () async {
      error = PlatformException(code: 'boom');
      expect(await subject().hasStepPermission(), isFalse);
      expect(await subject().requestStepPermission(), isFalse);
    });
  });

  group('permission is asked for, never assumed', () {
    test('hasStepPermission does not prompt', () async {
      reply = false;
      await subject().hasStepPermission();
      expect(calls.single.method, 'hasPermission', reason: 'the checking call, not the asking one');
    });

    test('requestStepPermission is a separate, explicit call', () async {
      reply = true;
      expect(await subject().requestStepPermission(), isTrue);
      expect(calls.single.method, 'requestPermission');
    });
  });
}
