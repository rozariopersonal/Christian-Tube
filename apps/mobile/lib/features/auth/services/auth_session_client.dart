import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/user.dart';

class SessionUnrecoverableException implements Exception {
  final int statusCode;
  final String message;
  SessionUnrecoverableException(this.statusCode, this.message);

  @override
  String toString() => 'SessionUnrecoverableException($statusCode): $message';
}

class SessionTransientException implements Exception {
  final String message;
  SessionTransientException(this.message);

  @override
  String toString() => 'SessionTransientException: $message';
}

class AuthSessionResult {
  final String accessToken;
  final String refreshToken;
  final String sessionId;
  final int expiresIn;
  final User? user;

  const AuthSessionResult({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
    required this.expiresIn,
    this.user,
  });
}

class AuthSessionClient {
  final Dio _dio;

  AuthSessionClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  Future<AuthSessionResult> exchangeGoogle({
    required String idToken,
    required String deviceId,
    String? deviceLabel,
  }) async {
    final res = await _post('/api/auth/google', {
      'idToken': idToken,
      'deviceId': deviceId,
      if (deviceLabel != null) 'deviceLabel': deviceLabel,
    });
    return _parseSessionResult(res);
  }

  Future<AuthSessionResult> refresh({
    required String sessionId,
    required String refreshToken,
  }) async {
    final res = await _post('/api/auth/refresh', {
      'sessionId': sessionId,
      'refreshToken': refreshToken,
    });
    return _parseSessionResult(res);
  }

  Future<void> logout({required String accessToken}) async {
    try {
      await _dio.post(
        '/api/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } catch (_) {
      // Best-effort only
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(path, data: body);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw SessionTransientException('Unexpected non-JSON auth response');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw SessionUnrecoverableException(
          status!,
          e.response?.data?.toString() ?? 'Unauthorized',
        );
      }
      throw SessionTransientException(e.message ?? 'Network or server error');
    }
  }

  AuthSessionResult _parseSessionResult(Map<String, dynamic> data) {
    final userRaw = data['user'];
    return AuthSessionResult(
      accessToken: (data['accessToken'] ?? '').toString(),
      refreshToken: (data['refreshToken'] ?? '').toString(),
      sessionId: (data['sessionId'] ?? '').toString(),
      expiresIn: (data['expiresIn'] as num?)?.toInt() ?? 900,
      user: userRaw is Map
          ? User.fromJson(Map<String, dynamic>.from(userRaw))
          : null,
    );
  }
}
