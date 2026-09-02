import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/data/datasources/remote/diary_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/plan_remote_data_source.dart';

/// Answers with one canned JSON body.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

const _base = 'http://192.168.2.18:3001/api/v1';

Dio _dioReturning(Object body) =>
    Dio(BaseOptions(baseUrl: _base))..httpClientAdapter = _StubAdapter(body);

/// The options endpoint is keyed by slot (D-85).
Map<String, List<Map<String, dynamic>>> _lunch(List<Map<String, dynamic>> foods) => {
  'lunch': foods,
};

void main() {
  /// The server sends a PATH, because only the client knows which host it is talking to. Left
  /// relative it reaches `CachedNetworkImage` as "/food-images/x.jpg" — not a URL it can fetch — so
  /// every picture silently falls back to its placeholder and the screen looks empty rather than
  /// broken. `FoodOption.absolute` existed and simply was not called; nothing noticed (D-84).
  group('food image paths are resolved against the API base URL', () {
    test('plan options', () async {
      final source = PlanRemoteDataSource(
        _dioReturning(
          _lunch([
            {
              'id': 'f1',
              'name': 'Aloo gobhi',
              'kcal_per_100g': 120,
              'image_url': '/food-images/aloo-gobhi.jpg',
              'image_attribution': 'Someone / CC BY-SA 4.0',
            },
          ]),
        ),
      );

      final options = (await source.options()).getOrElse(() => {});
      expect(options['lunch']!.single.imageUrl, '$_base/food-images/aloo-gobhi.jpg');
    });

    test('food search', () async {
      final source = DiaryRemoteDataSource(
        _dioReturning([
          {
            'id': 'f1',
            'name': 'Roti',
            'kcal': 297,
            'measures': <dynamic>[],
            'image_url': '/food-images/roti.jpg',
          },
        ]),
      );

      final foods = (await source.searchFoods('roti')).getOrElse(() => []);
      expect(foods.single.imageUrl, '$_base/food-images/roti.jpg');
    });

    test('a food with no photograph stays null rather than becoming the base URL', () async {
      final source = PlanRemoteDataSource(
        _dioReturning(
          _lunch([
            {'id': 'f1', 'name': 'Amla', 'kcal_per_100g': 44, 'image_url': null},
          ]),
        ),
      );

      final options = (await source.options()).getOrElse(() => {});
      expect(options['lunch']!.single.imageUrl, isNull);
    });

    test('an already-absolute URL is left alone', () async {
      final source = PlanRemoteDataSource(
        _dioReturning(
          _lunch([
            {
              'id': 'f1',
              'name': 'Dal',
              'kcal_per_100g': 120,
              'image_url': 'https://cdn.example.test/dal.jpg',
            },
          ]),
        ),
      );

      final options = (await source.options()).getOrElse(() => {});
      expect(options['lunch']!.single.imageUrl, 'https://cdn.example.test/dal.jpg');
    });
  });
}
