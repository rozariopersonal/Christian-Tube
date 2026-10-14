import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/short.dart';
import 'shorts_subscription_filter.dart';

class CommunityShortsController extends ChangeNotifier {
  static const String _cacheKeyAll = 'ct_cached_community_shorts';

  /// Injectable for tests; defaults to the real API client.
  final ApiClient apiClient;

  List<Short> _shorts = [];
  List<Short> get shorts => _shorts;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  bool _isAuthenticated = false;
  Set<String> _subscribedChannelIds = const {};
  Set<String>? _candidateChannelIds;

  CommunityShortsController({ApiClient? apiClient})
      : apiClient = apiClient ?? ApiClient() {
    _loadCachedShorts();
  }

  /// Active channel filter: `null` means show every short.
  Set<String>? get _effectiveChannelIds {
    if (!_isAuthenticated || _subscribedChannelIds.isEmpty) return null;
    final ids = _candidateChannelIds;
    if (ids == null || ids.isEmpty) return null;
    return ids;
  }

  /// Cache key scoped to the active filter so a signed-out user (or a user
  /// with no subscriptions) never sees a stale subscriptions-filtered snapshot,
  /// and vice versa. Exposed for test assertions.
  String get activeCacheKey {
    final ids = _effectiveChannelIds;
    if (ids == null) return _cacheKeyAll;
    return '${_cacheKeyAll}_sub_${_stableHash(_joinedSortedIds(ids))}';
  }

  static String _joinedSortedIds(Set<String> ids) {
    final list = ids.toList()..sort();
    return list.join(',');
  }

  static bool _filtersEqual(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// Stable length-bounded hash (31-bit) so the filter-scoped cache key is
  /// identical across runs and platforms. All arithmetic stays well within the
  /// 53-bit safe-integer range even on web, so the result never varies.
  static String _stableHash(String input) {
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = ((hash * 0x10CD5) + unit) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Recomputes the subscriptions filter from the current auth + subscription
  /// state. Refetches (and resets the feed) only when the resolved candidate
  /// set actually changed.
  Future<void> updateSubscriptionContext({
    required bool isAuthenticated,
    required Set<String> subscribedChannelIds,
  }) async {
    final previous = _effectiveChannelIds;
    _isAuthenticated = isAuthenticated;
    _subscribedChannelIds = subscribedChannelIds;
    _candidateChannelIds = resolveSubscribedChannelIds(
      isAuthenticated: isAuthenticated,
      subscribedChannelIds: subscribedChannelIds,
    );

    if (_filtersEqual(previous, _effectiveChannelIds)) {
      _safeNotify();
      return;
    }

    // Filter mode changed: reset pagination, swap to the matching cache, and
    // refetch from the network.
    _page = 1;
    _hasMore = true;
    _shorts = [];
    _isLoading = true;
    await _loadCachedShorts();
    _safeNotify();
    return fetchShorts();
  }

  /// Loads the last-fetched shorts from disk immediately so the feed can
  /// render without waiting on the network. A background refresh then updates
  /// it in place (stale-while-revalidate).
  Future<void> _loadCachedShorts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(activeCacheKey);
      if (cachedJson == null || cachedJson.isEmpty) return;
      final List<dynamic> list = jsonDecode(cachedJson);
      final cached = list
          .whereType<Map<String, dynamic>>()
          .map((j) => Short.fromJson(j))
          .toList();
      if (cached.isEmpty) return;
      _shorts = cached;
      _isLoading = false;
      _safeNotify();
    } catch (_) {
      // Corrupt/old cache is non-fatal; fall through to the network.
    }
  }

  Future<void> _saveCachedShorts(List<Short> shorts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        activeCacheKey,
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
      _safeNotify();
    }
  }

  Future<void> fetchShorts() async {
    final filterSnapshot = _effectiveChannelIds == null
        ? null
        : Set<String>.of(_effectiveChannelIds!);
    _page = 1;
    _hasMore = true;
    // Only block the whole feed on the network when we have nothing to show yet.
    _isLoading = _shorts.isEmpty;
    _safeNotify();

    try {
      final response = await apiClient.dio.get(
        '/videos',
        queryParameters: {
          'type': 'SHORT',
          'limit': 30,
          'offset': 0,
          if (filterSnapshot != null) 'channelIds': filterSnapshot.join(','),
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        // Ignore a response that resolved under a now-stale filter mode.
        if (!_filtersEqual(filterSnapshot, _effectiveChannelIds)) return;
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
          _safeNotify();
          await _saveCachedShorts(shortsOnly);
          return;
        }
      }

      _shorts = [];
      _isLoading = false;
      _safeNotify();
    } catch (e) {
      debugPrint('Error fetching shorts: $e');
      if (_filtersEqual(filterSnapshot, _effectiveChannelIds)) {
        _shorts = [];
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> loadMoreShorts() async {
    if (_isLoadingMore || !_hasMore) return;

    final filterSnapshot = _effectiveChannelIds == null
        ? null
        : Set<String>.of(_effectiveChannelIds!);
    _isLoadingMore = true;
    _safeNotify();

    try {
      final nextPage = _page + 1;
      final offset = (nextPage - 1) * 30;
      final response = await apiClient.dio.get(
        '/videos',
        queryParameters: {
          'type': 'SHORT',
          'limit': 30,
          'offset': offset,
          if (filterSnapshot != null) 'channelIds': filterSnapshot.join(','),
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        if (!_filtersEqual(filterSnapshot, _effectiveChannelIds)) return;
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
      _safeNotify();
    }
  }

  void insertShortAtBeginning(Short short) {
    _shorts.insert(0, short);
    _safeNotify();
  }
}
