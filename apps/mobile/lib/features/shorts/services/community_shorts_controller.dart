import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/short.dart';

class CommunityShortsController extends ChangeNotifier {
  static const String _cacheKey = 'ct_cached_community_shorts';

  final ApiClient _apiClient = ApiClient();

  List<Short> _shorts = [];
  List<Short> get shorts => _shorts;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  CommunityShortsController() {
    _loadCachedShorts();
  }

  /// Loads the last-fetched shorts from disk immediately so the feed can
  /// render without waiting on the network. A background refresh then updates
  /// it in place (stale-while-revalidate).
  Future<void> _loadCachedShorts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson == null || cachedJson.isEmpty) return;
      final List<dynamic> list = jsonDecode(cachedJson);
      final cached = list
          .whereType<Map<String, dynamic>>()
          .map((j) => Short.fromJson(j))
          .toList();
      if (cached.isEmpty) return;
      _shorts = cached;
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      // Corrupt/old cache is non-fatal; fall through to the network.
    }
  }

  Future<void> _saveCachedShorts(List<Short> shorts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(shorts.take(50).map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }


  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  int _page = 1;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  String _filter = 'all';
  String get filter => _filter;

  List<Short> get filteredShorts {
    if (_filter == 'popular') {
      final list = List<Short>.from(_shorts);
      list.sort((a, b) => b.viewCount.compareTo(a.viewCount));
      return list;
    } else if (_filter == 'recent') {
      final list = List<Short>.from(_shorts);
      list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return list;
    }
    return _shorts;
  }

  void setFilter(String newFilter) {
    if (_filter != newFilter) {
      _filter = newFilter;
      notifyListeners();
    }
  }

  Future<void> fetchShorts() async {
    _page = 1;
    _hasMore = true;
    // Only block the whole feed on the network when we have nothing to show yet.
    _isLoading = _shorts.isEmpty;
    notifyListeners();

    try {
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 30, 'offset': 0},
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
          final shortsOnly = allVideos.where((s) {
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

          _shorts = shortsOnly;
          _isLoading = false;
          notifyListeners();
          await _saveCachedShorts(shortsOnly);
          return;
        }
      }

      _shorts = [];
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching shorts: $e');
      _shorts = [];
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreShorts() async {
    if (_isLoadingMore || !_hasMore) return;
    
    _isLoadingMore = true;
    notifyListeners();

    try {
      final nextPage = _page + 1;
      final offset = (nextPage - 1) * 30;
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {'type': 'SHORT', 'limit': 30, 'offset': offset},
      );
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);

        final newVideos = list
            .whereType<Map<String, dynamic>>()
            .map((v) => Short.fromJson(v))
            .where((s) => s.durationSeconds <= 180 || s.type == 'SHORT')
            .toList();

        if (newVideos.isEmpty) {
          _hasMore = false;
        } else {
          _page = nextPage;
          final existingIds = _shorts.map((s) => s.id).toSet();
          final uniqueNew = newVideos.where((s) => !existingIds.contains(s.id)).toList();
          _shorts.addAll(uniqueNew);
        }
      }
    } catch (e) {
      debugPrint('Load more shorts error: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void insertShortAtBeginning(Short short) {
    _shorts.insert(0, short);
    notifyListeners();
  }
}
