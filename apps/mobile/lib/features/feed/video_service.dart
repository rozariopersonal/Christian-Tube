import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../core/config/app_config.dart';

class VideoService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

  List<Video> _allVideos = [];
  List<Video> _displayedVideos = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedCategory = 'All';
  String? _selectedChannelId;
  bool _subscribedOnly = false;
  Set<String> _subscribedChannelIds = {};

  List<Video> get videos => _displayedVideos;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedCategory => _selectedCategory;
  String? get selectedChannelId => _selectedChannelId;
  bool get subscribedOnly => _subscribedOnly;

  List<String> get categories => AppConfig.defaultCategories;

  void updateSubscribedChannelIds(Set<String> ids) {
    _subscribedChannelIds = ids;
    _applyFilters();
  }

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
            if (_selectedChannelId != null) 'channelId': _selectedChannelId,
          },
        );
      } catch (_) {
        // Fallback to /videos route
        response = await _apiClient.dio.get(
          '/videos',
          queryParameters: {
            if (_selectedCategory != 'All') 'category': _selectedCategory,
            if (_selectedChannelId != null) 'channelId': _selectedChannelId,
          },
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List
            ? raw
            : (raw['videos'] ?? raw['data'] ?? raw['items'] ?? []);
        
        _allVideos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Video.fromJson(v))
            .toList();

        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error loading video feed: $e');
      _errorMessage = 'Failed to load videos. Please check your connection.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyFilters() {
    var filtered = List<Video>.from(_allVideos);

    if (_selectedChannelId != null) {
      filtered = filtered.where((v) => v.channelId == _selectedChannelId).toList();
    } else if (_subscribedOnly && _subscribedChannelIds.isNotEmpty) {
      filtered = filtered.where((v) => _subscribedChannelIds.contains(v.channelId)).toList();
    }

    _displayedVideos = filtered;
    notifyListeners();
  }

  void selectCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
    fetchFeed(refresh: true);
  }

  void selectChannel(String? channelId) {
    _selectedChannelId = channelId;
    _subscribedOnly = false;
    _applyFilters();
  }

  void toggleSubscribedOnly() {
    _subscribedOnly = !_subscribedOnly;
    _selectedChannelId = null;
    _applyFilters();
  }
}
