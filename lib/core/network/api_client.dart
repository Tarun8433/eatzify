import 'package:dio/dio.dart';

/// dio, configured once. docs/06 §topology, docs/09 §2.
class ApiClient {
  ApiClient({required String baseUrl, Duration timeout = const Duration(seconds: 20)})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: timeout,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          headers: const {'Accept': 'application/json'},
          // We handle every non-2xx through mapDioError rather than letting dio decide.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );

  final Dio dio;

  /// Attaches the bearer token and refreshes once on a 401.
  ///
  /// `onRefresh` returns a new access token or null. A null means the refresh token is dead — docs/09
  /// says reuse revokes the family — and the caller is expected to have cleared the session.
  void attachAuth({
    required String? Function() accessToken,
    required Future<String?> Function() onRefresh,
  }) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = accessToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (e, handler) async {
          final isAuthCall = e.requestOptions.path.startsWith('/auth/');
          if (e.response?.statusCode != 401 || isAuthCall) return handler.next(e);

          // Retry exactly once. A refresh loop on a revoked token is how an app hammers the API
          // and burns a user's data allowance in the background.
          final fresh = await onRefresh();
          if (fresh == null) return handler.next(e);

          final retried = e.requestOptions..headers['Authorization'] = 'Bearer $fresh';
          try {
            handler.resolve(await dio.fetch<dynamic>(retried));
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
  }
}
