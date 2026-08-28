import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';

class VideoService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  List<Video> _videos = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 25;

  String? _selectedCategory;
  String? _selectedChannelId;
  Set<String> _subscribedChannelIds = {};
  bool _onlySubscribed = false;

  VideoService() {
    _loadCachedFeed();
  }

  Future<void> _loadCachedFeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('ct_cached_home_feed');
      if (cachedJson != null && _videos.isEmpty) {
        final List<dynamic> list = jsonDecode(cachedJson);
        _videos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Video.fromJson(v))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveCachedFeed(List<Video> videos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(videos.take(25).map((v) => v.toJson()).toList());
      await prefs.setString('ct_cached_home_feed', jsonStr);
    } catch (_) {}
  }

  List<Video> get videos => _videos;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get selectedCategory => _selectedCategory;
  String? get selectedChannelId => _selectedChannelId;
  bool get onlySubscribed => _onlySubscribed;

  void updateSubscribedChannelIds(Set<String> ids) {
    _subscribedChannelIds = ids;
  }

  void setFilter({String? category, String? channelId, bool? onlySubscribed}) {
    _selectedCategory = category;
    _selectedChannelId = channelId;
    if (onlySubscribed != null) {
      _onlySubscribed = onlySubscribed;
    }
    refreshVideos();
  }

  Future<void> refreshVideos() async {
    _offset = 0;
    _hasMore = true;
    if (_selectedCategory != null && _selectedCategory != 'All') {
      _videos = [];
    }
    await fetchVideos();
  }

  Future<void> fetchVideos() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      final Map<String, dynamic> queryParams = {
        'limit': _limit,
        'offset': _offset,
        'type': 'VIDEO',
      };

      if (_selectedCategory != null && _selectedCategory != 'All') {
        queryParams['category'] = _selectedCategory;
      }

      if (_selectedChannelId != null && _selectedChannelId!.isNotEmpty) {
        queryParams['channelId'] = _selectedChannelId;
      } else if (_onlySubscribed) {
        if (_subscribedChannelIds.isEmpty) {
          _videos = [];
          _isLoading = false;
          _hasMore = false;
          notifyListeners();
          return;
        }
        queryParams['channelIds'] = _subscribedChannelIds.join(',');
      }

      dynamic response;
      try {
        response = await _apiClient.dio.get('/api/videos', queryParameters: queryParams);
      } catch (_) {
        response = await _apiClient.dio.get('/videos', queryParameters: queryParams);
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        final newVideos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Video.fromJson(v))
            .toList();

        if (_offset == 0) {
          _videos = newVideos;
          if (_selectedCategory == null || _selectedCategory == 'All') {
            _saveCachedFeed(newVideos);
          }
        } else {
          _videos.addAll(newVideos);
        }

        _offset += newVideos.length;
        if (newVideos.length < _limit) {
          _hasMore = false;
        }
      }
    } catch (e) {
      debugPrint('Error fetching videos: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
