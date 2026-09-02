import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Request/response logging for the debug console. Debug builds only.
///
/// CLAUDE.md rule 9 and docs/13: no PII in logs. dio's own `LogInterceptor` prints headers and
/// bodies verbatim, which would put bearer tokens, OTPs, phone numbers and declared health
/// conditions on the console and into any attached crash reporter. So every sensitive key is
/// redacted here rather than the whole body being dumped.
///
/// This is a developer tool, not telemetry — it must never reach a release build, which is why the
/// guard is `kDebugMode` and not a flag someone can flip in config.
class ApiLogInterceptor extends Interceptor {
  ApiLogInterceptor({this.maxBodyChars = 1000, this.onLog});

  /// Test seam — production always goes to the debug console.
  final void Function(String)? onLog;

  /// Bodies longer than this are truncated — a food list would otherwise flood the console.
  final int maxBodyChars;

  /// Anything whose key matches is replaced. Health fields are here because docs/13 treats a
  /// declared condition as sensitive personal data, not merely private.
  static const _redactedKeys = {
    'access',
    'refresh',
    'token',
    'accessToken',
    'refreshToken',
    'authorization',
    'password',
    'oldPassword',
    'hash',
    'otp',
    'phone_e164',
    'phone',
    'conditions',
    'allergies',
    'health_profile',
    'screened_special_diet',
    'screened_insulin_or_kidney',
    'screened_eating_disorder',
    'photo',
    'photo_url',
    'email',
  };

  static const _redacted = '***';

  final _startTimes = <int, DateTime>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      _startTimes[options.hashCode] = DateTime.now();
      _log('→ ${options.method} ${options.path}${_query(options)}');
      final body = _describe(options.data);
      if (body != null) _log('  body $body');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final o = response.requestOptions;
      _log('← ${response.statusCode} ${o.method} ${o.path}${_elapsed(o)}');
      final body = _describe(response.data);
      if (body != null) _log('  body $body');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final o = err.requestOptions;
      final status = err.response?.statusCode;
      _log('✗ ${status ?? err.type.name} ${o.method} ${o.path}${_elapsed(o)}');
      // The HOST, but only when the connection itself failed. "connectionTimeout POST
      // /profile/onboarding" does not say which machine was not answering, and the answer was that
      // the app had a stale LAN address baked into it. One line turns that into a ten-second read.
      if (err.response == null) _log('  host ${o.baseUrl}');
      // The error body carries `user_message`, which is the whole reason to look at a failure.
      final body = _describe(err.response?.data);
      if (body != null) _log('  body $body');
      if (status == null) _log('  ${err.message}');
    }
    handler.next(err);
  }

  String _query(RequestOptions options) {
    if (options.queryParameters.isEmpty) return '';
    return '?${_redactMap(options.queryParameters)}';
  }

  String _elapsed(RequestOptions options) {
    final started = _startTimes.remove(options.hashCode);
    if (started == null) return '';
    return '  ${DateTime.now().difference(started).inMilliseconds}ms';
  }

  /// FormData is a file upload — never log its contents.
  String? _describe(dynamic data) {
    if (data == null) return null;
    if (data is FormData) return '<multipart ${data.files.length} file(s)>';

    final redacted = _redact(data);
    if (redacted == null) return null;

    final text = redacted is String ? redacted : jsonEncode(redacted);
    return text.length > maxBodyChars
        ? '${text.substring(0, maxBodyChars)}… (${text.length} chars)'
        : text;
  }

  dynamic _redact(dynamic value) {
    if (value is Map) return _redactMap(value);
    if (value is List) return value.map(_redact).toList();
    return value;
  }

  Map<String, dynamic> _redactMap(Map<dynamic, dynamic> map) => {
    for (final entry in map.entries)
      entry.key.toString(): _redactedKeys.contains(entry.key.toString())
          ? _redacted
          : _redact(entry.value),
  };

  void _log(String message) {
    final sink = onLog;
    if (sink != null) {
      sink(message);
      return;
    }
    developer.log(message, name: 'api');
  }
}
