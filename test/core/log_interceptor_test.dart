import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/network/log_interceptor.dart';

/// A leak here is silent — it reaches the console and any attached crash reporter without any
/// visible symptom, so the redaction is tested directly rather than trusted.
void main() {
  late ApiLogInterceptor interceptor;
  late List<String> lines;

  setUp(() {
    lines = [];
    interceptor = ApiLogInterceptor(onLog: lines.add);
  });

  String logOf(dynamic body) {
    interceptor.onRequest(
      RequestOptions(path: '/x', method: 'POST', data: body),
      RequestInterceptorHandler(),
    );
    return lines.join('\n');
  }

  test('redacts credentials', () {
    final out = logOf({
      'access': 'ey.secret.token',
      'refresh': 'refresh-secret',
      'password': 'hunter2',
    });

    expect(out, isNot(contains('ey.secret.token')));
    expect(out, isNot(contains('refresh-secret')));
    expect(out, isNot(contains('hunter2')));
  });

  test('redacts the phone number and OTP (docs/09 §3: never log an OTP)', () {
    final out = logOf({'phone_e164': '+919876543210', 'otp': '123456'});

    expect(out, isNot(contains('919876543210')));
    expect(out, isNot(contains('123456')));
  });

  test('redacts declared health data (docs/13)', () {
    final out = logOf({
      'health_profile': {
        'conditions': ['pcos'],
        'allergies': ['peanut'],
      },
    });

    expect(out, isNot(contains('pcos')));
    expect(out, isNot(contains('peanut')));
  });

  test('redacts sensitive keys nested inside a list', () {
    final out = logOf({
      'items': [
        {'otp': '999999'},
      ],
    });

    expect(out, isNot(contains('999999')));
  });

  test('keeps non-sensitive fields readable — a log nobody can read is useless', () {
    final out = logOf({'goal': 'fat_loss', 'activity': 'moderate'});

    expect(out, contains('fat_loss'));
    expect(out, contains('moderate'));
  });

  test('never logs the contents of a file upload', () {
    final out = logOf(FormData.fromMap({'note': 'x'}));

    expect(out, contains('multipart'));
    expect(out, isNot(contains('note')));
  });

  test('truncates a long body instead of flooding the console', () {
    final out = logOf({'items': List.filled(500, 'aaaaaaaa')});

    expect(out.length, lessThan(1400));
    expect(out, contains('chars'));
  });

  test('logs the method and path so a request is identifiable', () {
    final out = logOf({'goal': 'fat_loss'});

    expect(out, contains('POST'));
    expect(out, contains('/x'));
  });
}
