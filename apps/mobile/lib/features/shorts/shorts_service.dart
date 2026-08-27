import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import 'shorts_feed_screen.dart';

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
      // 1. Try querying /videos?type=SHORT
      final response = await _apiClient.dio.get('/videos?type=SHORT');
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['shorts'] ?? raw['data'] ?? []);
        if (list.isNotEmpty) {
          _shorts = list
              .whereType<Map<String, dynamic>>()
              .map((s) => Short.fromJson(s))
              .toList();
          return;
        }
      }

      // 2. Fallback: Query all /videos and classify on the frontend using Short.isShort
      final allResponse = await _apiClient.dio.get('/videos');
      if (allResponse.statusCode == 200 && allResponse.data != null) {
        final dynamic raw = allResponse.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        final detected = list
            .whereType<Map<String, dynamic>>()
            .where(Short.isShort)
            .map((s) => Short.fromJson(s))
            .toList();

        if (detected.isNotEmpty) {
          _shorts = detected;
          return;
        }
      }

      // 3. Fallback to curated seed shorts
      _shorts = ShortsFeedScreen.seedShorts;
    } catch (e) {
      debugPrint('Error fetching shorts, falling back to seed shorts: $e');
      _shorts = ShortsFeedScreen.seedShorts;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
