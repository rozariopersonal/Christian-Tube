import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';

class ShortsService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  List<Short> _shorts = [];
  bool _isLoading = false;

  List<Short> get shorts => _shorts;
  bool get isLoading => _isLoading;

  Future<void> fetchShorts() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 100},
      );
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        final allVideos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Short.fromJson(v))
            .toList();

        if (allVideos.isNotEmpty) {
          // STRICT: Only include videos that are under 3 minutes (duration <= 180 seconds) or explicitly SHORT
          _shorts = allVideos.where((s) {
            if (s.durationSeconds > 0) {
              return s.durationSeconds <= 180;
            }
            final durSec = Short.parseDurationInSeconds(s.duration);
            if (durSec > 0) {
              return durSec <= 180;
            }
            final isShortUrl = s.videoUrl.toLowerCase().contains('/shorts/');
            final isShortTitle = s.title.toLowerCase().contains('#short');
            final isShortDesc =
                (s.description ?? '').toLowerCase().contains('#short');
            return isShortUrl || isShortTitle || isShortDesc || s.type == 'SHORT';
          }).toList();
          return;
        }
      }

      _shorts = [];
    } catch (e) {
      debugPrint('Error fetching shorts from backend: $e');
      _shorts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
