import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/data/datasources/remote/profile_remote_data_source.dart';

/// The server returns a path relative to its own origin. Resolving it client-side is what keeps the
/// image loading when `BACKEND_DOMAIN` says `localhost` — which a phone can never reach (D-32).
void main() {
  late ProfileRemoteDataSource source;
  late DioAdapterStub adapter;

  setUp(() {
    final dio = Dio(BaseOptions(baseUrl: 'http://192.168.2.18:3001/api/v1'));
    adapter = DioAdapterStub();
    dio.httpClientAdapter = adapter;
    source = ProfileRemoteDataSource(dio);
  });

  Future<String?> photoUrlFor(dynamic value) async {
    adapter.body = {
      'profile': {
        'age_years': 29,
        'height_cm': 170,
        'weight_kg': 70,
        'sex_at_birth': 'male',
        'goal': 'fat_loss',
        'activity': 'light',
        'food_preference': 'veg',
      },
      'health_profile': {'version': 1, 'conditions': <String>[], 'allergies': <String>[]},
      'photo_url': value,
    };
    final result = await source.profile();
    return result.fold((_) => null, (p) => p?.photoUrl);
  }

  test('resolves a relative path against the client base URL, not the server origin', () async {
    expect(
      await photoUrlFor('/api/v1/files/abc.jpg'),
      'http://192.168.2.18:3001/api/v1/files/abc.jpg',
    );
  });

  test('leaves an absolute URL untouched', () async {
    expect(await photoUrlFor('https://cdn.example.com/abc.jpg'), 'https://cdn.example.com/abc.jpg');
  });

  test('null stays null — no photo is not a broken URL', () async {
    expect(await photoUrlFor(null), isNull);
  });

  test('an empty string is treated as no photo', () async {
    expect(await photoUrlFor(''), isNull);
  });
}

/// Returns a canned JSON body without touching the network.
class DioAdapterStub implements HttpClientAdapter {
  Map<String, dynamic> body = {};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    _encode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  static String _encode(Map<String, dynamic> map) {
    final buffer = StringBuffer('{');
    var first = true;
    map.forEach((k, v) {
      if (!first) buffer.write(',');
      first = false;
      buffer.write('"$k":${_value(v)}');
    });
    buffer.write('}');
    return buffer.toString();
  }

  static String _value(dynamic v) {
    if (v == null) return 'null';
    if (v is num) return '$v';
    if (v is List) return '[${v.map(_value).join(',')}]';
    if (v is Map) return _encode(Map<String, dynamic>.from(v));
    return '"$v"';
  }
}
