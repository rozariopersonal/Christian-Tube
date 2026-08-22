import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../core/config/app_config.dart';

class VideoService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

  List<Video> _videos = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedCategory = 'All';

  List<Video> get videos => _videos;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedCategory => _selectedCategory;

  List<String> get categories => AppConfig.defaultCategories;

  Future<void> fetchFeed({bool refresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      Response response;
      try {
        response = await _apiClient.dio.get(
          '/api/videos',
          queryParameters: {
            if (_selectedCategory != 'All') 'category': _selectedCategory,
          },
        );
      } catch (_) {
        // Fallback to /videos route
        response = await _apiClient.dio.get(
          '/videos',
          queryParameters: {
            if (_selectedCategory != 'All') 'category': _selectedCategory,
          },
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List
            ? raw
            : (raw['videos'] ?? raw['data'] ?? raw['items'] ?? []);
        
        _videos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Video.fromJson(v))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading video feed: $e');
      _errorMessage = 'Failed to load videos. Please check your connection.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
    fetchFeed(refresh: true);
  }
}
