import 'package:dio/dio.dart';
import '../../../../core/api/api_client.dart';
import '../models/audio_processor_models.dart';

class UploadSessionResponse {
  final String uploadSessionId;
  final String uploadUrl;

  const UploadSessionResponse({
    required this.uploadSessionId,
    required this.uploadUrl,
  });
}

class AdminAudioProcessorApi {
  final Dio _dio;

  AdminAudioProcessorApi({Dio? dio}) : _dio = dio ?? _buildColdStartDio();

  static Dio _buildColdStartDio() {
    // Reuse ApiClient's auth & RefreshCoordinator interceptors with generous
    // timeouts to handle Render cold starts cleanly in background isolates.
    final client = ApiClient();
    client.dio.options = client.dio.options.copyWith(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    );
    return client.dio;
  }

  Future<List<PendingAudioVideo>> fetchPending({int hours = 72}) async {
    final resp = await _dio.get(
      '/admin/audio-processor/pending',
      queryParameters: {'hours': hours},
    );
    final raw = (resp.data is Map ? resp.data['data'] : resp.data) as List?;
    if (raw == null) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PendingAudioVideo.fromJson)
        .toList(growable: false);
  }

  /// Returns true if claimed; false if another admin already claimed (409).
  Future<bool> claimVideo(String videoId) async {
    try {
      await _dio.post(
        '/admin/audio-processor/claim',
        data: {'videoId': videoId},
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) return false;
      rethrow;
    }
  }

  Future<UploadSessionResponse> createUploadSession({
    required String videoId,
    required String mime,
    required int size,
  }) async {
    final resp = await _dio.post(
      '/admin/audio-processor/upload-session',
      data: {'videoId': videoId, 'mime': mime, 'size': size},
    );
    final data = resp.data as Map<String, dynamic>;
    return UploadSessionResponse(
      uploadSessionId: (data['uploadSessionId'] ?? '').toString(),
      uploadUrl: (data['uploadUrl'] ?? '').toString(),
    );
  }

  Future<void> completeUpload({
    required String uploadSessionId,
    required int durationSeconds,
    required int bytesUploaded,
  }) async {
    await _dio.post(
      '/admin/audio-processor/complete',
      data: {
        'uploadSessionId': uploadSessionId,
        'durationSeconds': durationSeconds,
        'bytesUploaded': bytesUploaded,
      },
    );
  }

  Future<void> markShort(String videoId) async {
    await _dio.post(
      '/admin/audio-processor/mark-short',
      data: {'videoId': videoId},
    );
  }

  Future<void> markIgnored(String videoId, {String? reason}) async {
    await _dio.post(
      '/admin/audio-processor/ignore',
      data: {'videoId': videoId, if (reason != null) 'reason': reason},
    );
  }

  Future<void> reportFailure({
    required String videoId,
    required String error,
    bool permanent = false,
  }) async {
    await _dio.post(
      '/admin/audio-processor/fail',
      data: {'videoId': videoId, 'error': error, 'permanent': permanent},
    );
  }

  Future<AudioProcessorReport> fetchReport() async {
    final resp = await _dio.get('/admin/audio-processor/report');
    final data = (resp.data is Map ? resp.data['data'] : resp.data)
        as Map<String, dynamic>?;
    return AudioProcessorReport.fromJson(data ?? const {});
  }

  Future<void> registerDeviceToken(String token) async {
    await _dio.post(
      '/admin/audio-processor/device-token',
      data: {'token': token},
    );
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _dio.delete(
      '/admin/audio-processor/device-token',
      data: {'token': token},
    );
  }
}
