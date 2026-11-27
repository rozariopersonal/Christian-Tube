import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/video.dart';
import '../../../core/services/user_sync_service.dart';

class WatchLaterService extends ChangeNotifier {
  static final WatchLaterService instance = WatchLaterService._internal();
  factory WatchLaterService() => instance;

  static const String _storagePrefix = 'watch_later_v1_';

  final UserSyncService _sync;
  final String? _userIdOverride;

  List<Video> _videos = [];
  bool _isLoading = false;
  bool _initialized = false;
  String? _loadedUserId;

  WatchLaterService._internal()
      : _sync = UserSyncService.instance,
        _userIdOverride = null;

  @visibleForTesting
  WatchLaterService.forTesting({
    UserSyncService? syncService,
    String? userId,
  })  : _sync = syncService ?? UserSyncService.instance,
        _userIdOverride = userId;

  List<Video> get videos => List.unmodifiable(_videos);
  int get count => _videos.length;
  bool get isLoading => _isLoading;

  String get _effectiveUserId {
    final override = _userIdOverride;
    if (override != null && override.isNotEmpty) return override;
    final active = _sync.activeUserId;
    if (active != null && active.isNotEmpty) return active;
    return 'guest';
  }

  String _storageKey(String userId) => '$_storagePrefix$userId';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sync.addListener(_onSyncStateChanged);
    await reloadForCurrentUser();
  }

  Future<void> reloadForCurrentUser() async {
    final userId = _effectiveUserId;
    _loadedUserId = userId;
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _videos = decoded
            .whereType<Map>()
            .map((m) => Video.fromJson(Map<String, dynamic>.from(m)))
            .where((v) => v.id.isNotEmpty)
            .toList();
      } else {
        _videos = [];
      }

      if (userId != 'guest') {
        final guestRaw = prefs.getString(_storageKey('guest'));
        if (guestRaw != null && guestRaw.isNotEmpty) {
          final guestList = (jsonDecode(guestRaw) as List<dynamic>)
              .whereType<Map>()
              .map((m) => Video.fromJson(Map<String, dynamic>.from(m)))
              .where((v) => v.id.isNotEmpty)
              .toList();
          final existingIds = _videos.map((v) => v.id).toSet();
          final migrated = guestList
              .where((v) => existingIds.add(v.id))
              .toList();
          if (migrated.isNotEmpty) {
            _videos = [...migrated, ..._videos];
            await prefs.setString(
              _storageKey(userId),
              jsonEncode(_videos.map((v) => v.toJson()).toList()),
            );
            for (final video in migrated) {
              unawaited(
                _sync.enqueueWatchItem(
                  itemType: UserSyncService.watchLaterType,
                  itemId: video.id,
                  isDeleted: false,
                ),
              );
            }
          }
          await prefs.remove(_storageKey('guest'));
        }
      }
    } catch (e) {
      debugPrint('WatchLaterService load warning: $e');
      _videos = [];
    } finally {
      _isLoading = false;
    }

    _mergeRemoteState(persist: true);
    notifyListeners();
  }

  Future<void> clearLocalState() async {
    _videos = [];
    _loadedUserId = null;
    notifyListeners();
  }

  bool isWatchLater(String videoId) {
    if (videoId.isEmpty) return false;
    return _videos.any((v) => v.id == videoId);
  }

  Future<bool> toggleWatchLater(Video video) async {
    if (video.id.isEmpty) return false;
    final exists = isWatchLater(video.id);
    if (exists) {
      await removeFromWatchLater(video.id);
      return false;
    }
    _videos = [video, ..._videos.where((v) => v.id != video.id)];
    notifyListeners();
    await _persist();
    unawaited(
      _sync.enqueueWatchItem(
        itemType: UserSyncService.watchLaterType,
        itemId: video.id,
        isDeleted: false,
      ),
    );
    return true;
  }

  Future<void> removeFromWatchLater(String videoId) async {
    if (videoId.isEmpty) return;
    _videos = _videos.where((v) => v.id != videoId).toList();
    notifyListeners();
    await _persist();
    unawaited(
      _sync.enqueueWatchItem(
        itemType: UserSyncService.watchLaterType,
        itemId: videoId,
        isDeleted: true,
      ),
    );
  }

  void _onSyncStateChanged() {
    if (_userIdOverride == null) {
      final active = _sync.activeUserId;
      if (active == null) {
        if (_loadedUserId != null && _loadedUserId != 'guest') {
          unawaited(clearLocalState());
        }
        return;
      }
      if (_loadedUserId != active) {
        unawaited(reloadForCurrentUser());
        return;
      }
    }
    final changed = _mergeRemoteState(persist: true);
    if (changed) {
      notifyListeners();
    }
  }

  bool _mergeRemoteState({required bool persist}) {
    final remote = _sync.remoteState;
    if (remote == null) return false;

    final remoteList = remote['watchLater'];
    if (remoteList is! List) return false;

    final tombstones = (remote['watchLaterTombstones'] as Map?) ?? const {};
    final pending = _sync.pendingOps;
    const pendingPrefix = '${UserSyncService.watchLaterType}:';

    final localById = {for (final v in _videos) v.id: v};
    final merged = <Video>[];
    final seen = <String>{};

    // Keep locally added pending items at the front so optimistic adds are preserved.
    for (final v in _videos) {
      final op = pending['$pendingPrefix${v.id}'];
      if (op != null && !op.isDeleted && seen.add(v.id)) {
        merged.add(v);
      }
    }

    for (final entry in remoteList.whereType<Map>()) {
      final videoMap = entry['video'] is Map
          ? Map<String, dynamic>.from(entry['video'] as Map)
          : Map<String, dynamic>.from(entry);
      final video = Video.fromJson(videoMap);
      if (video.id.isEmpty || seen.contains(video.id)) continue;

      final op = pending['$pendingPrefix${video.id}'];
      if (op?.isDeleted == true) continue;
      if (tombstones.containsKey(video.id) && op == null) continue;

      seen.add(video.id);
      merged.add(video);
    }

    // Keep any remaining local videos that are not tombstoned if remote had none?
    // Remote is authoritative for non-pending items, so anything removed remotely
    // without a pending add op is dropped.
    final changed = merged.length != _videos.length ||
        !_sameIds(merged, _videos) ||
        !_sameTitles(merged, localById);

    if (changed) {
      _videos = merged;
      if (persist) {
        unawaited(_persist());
      }
    }
    return changed;
  }

  bool _sameIds(List<Video> a, List<Video> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  bool _sameTitles(List<Video> next, Map<String, Video> prevById) {
    for (final v in next) {
      if (prevById[v.id]?.title != v.title) return false;
    }
    return true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _loadedUserId ?? _effectiveUserId;
      await prefs.setString(
        _storageKey(userId),
        jsonEncode(_videos.map((v) => v.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('WatchLaterService persist warning: $e');
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      _sync.removeListener(_onSyncStateChanged);
    }
    super.dispose();
  }
}
