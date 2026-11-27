import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import '../config/app_config.dart';
import '../../features/auth/services/auth_token_store.dart';
import '../../features/auth/services/refresh_coordinator.dart';

class ApiClient {
  static String get baseUrl => AppConfig.apiBaseUrl;
  late final Dio dio;

  static bool _isAuthEndpoint(String path) {
    return path.contains('/auth/google') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/logout');
  }

  ApiClient({
    AuthTokenStore? tokenStore,
    RefreshCoordinator? refreshCoordinator,
  }) {
    final store = tokenStore ?? AuthTokenStore.instance;
    final coordinator = refreshCoordinator ?? RefreshCoordinator.instance;

    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Auth interceptor runs BEFORE RetryInterceptor so 401 refreshes once and
    // is never replayed 3x by RetryInterceptor.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await store.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final status = error.response?.statusCode;
          final opts = error.requestOptions;
          if (status == 401 &&
              opts.extra['auth_retried'] != true &&
              !_isAuthEndpoint(opts.path)) {
            final newToken = await coordinator.refresh();
            if (newToken != null && newToken.isNotEmpty) {
              opts.headers['Authorization'] = 'Bearer $newToken';
              opts.extra['auth_retried'] = true;
              try {
                final response = await dio.fetch(opts);
                return handler.resolve(response);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );

    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
      ),
    );
  }
}
