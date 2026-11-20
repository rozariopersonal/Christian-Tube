import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/playlist.dart';
import '../../core/models/video.dart';
import '../../core/services/user_sync_service.dart';

class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal() {
    loadLocalHistory();
    UserSyncService.instance.addListener(_onSyncStateChanged);
  }

  final ApiClient _apiClient = ApiClient();
  static const String _historyStorageKey = 'user_watch_history_v1';
  static const String _playheadsStorageKey = 'video_playheads_map_v1';

  List<Playlist> _playlists = [];
  List<Video> _history = [];
  Map<String, Map<String, dynamic>> _playheads = {};
  List<Map<String, dynamic>> _registeredUsers = [];
  bool _isLoadingUsers = false;

  List<Playlist> get playlists => _playlists;
  List<Video> get history => _history;
  List<Map<String, dynamic>> get registeredUsers => _registeredUsers;
  bool get isLoadingUsers => _isLoadingUsers;

  Future<void> loadLocalHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        _history = list.map((v) => Video.fromJson(v as Map<String, dynamic>)).toList();
        notifyListeners();
      }
      final rawPlayheads = prefs.getString(_playheadsStorageKey);
      if (rawPlayheads != null && rawPlayheads.isNotEmpty) {
        final decoded = jsonDecode(rawPlayheads) as Map<String, dynamic>;
        _playheads = decoded.map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        );
      }
    } catch (e) {
      debugPrint('Error loading local watch history: $e');
    }
    // Non-blocking background sync from backend
    _syncHistoryAndPlayheadsFromBackend();
  }

  Future<void> _syncHistoryAndPlayheadsFromBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null || token.isEmpty) return;

      final histRes = await _apiClient.dio.get(
        '/api/user/playback',
        queryParameters: {'mediaType': 'video_history'},
      );
      if (histRes.statusCode == 200 && histRes.data is Map) {
        final payloadJson = (histRes.data as Map)['payloadJson'] as String?;
        if (payloadJson != null && payloadJson.isNotEmpty) {
          final List<dynamic> remoteList = jsonDecode(payloadJson);
          final existingIds = _history.map((v) => v.id).toSet();
          final merged = [..._history];
          for (final item in remoteList) {
            if (item is Map<String, dynamic>) {
              final videoMap = item['video'] is Map<String, dynamic>
                  ? item['video'] as Map<String, dynamic>
                  : item;
              final video = Video.fromJson(videoMap);
              if (video.id.isNotEmpty && !existingIds.contains(video.id)) {
                existingIds.add(video.id);
                merged.add(video);
              }
            }
          }
          _history = merged.take(100).toList();
          await prefs.setString(
            _historyStorageKey,
            jsonEncode(_history.map((v) => v.toJson()).toList()),
          );
          notifyListeners();
        }
      }

      final phRes = await _apiClient.dio.get(
        '/api/user/playback',
        queryParameters: {'mediaType': 'video_playheads'},
      );
      if (phRes.statusCode == 200 && phRes.data is Map) {
        final payloadJson = (phRes.data as Map)['payloadJson'] as String?;
        if (payloadJson != null && payloadJson.isNotEmpty) {
          final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
          for (final entry in decoded.entries) {
            if (entry.value is Map) {
              final remoteMap = Map<String, dynamic>.from(entry.value as Map);
              final remoteUpdated = (remoteMap['updatedAt'] as num?)?.toInt() ?? 0;
              final localUpdated =
                  (_playheads[entry.key]?['updatedAt'] as num?)?.toInt() ?? 0;
              if (remoteUpdated > localUpdated) {
                _playheads[entry.key] = remoteMap;
              }
            }
          }
          await prefs.setString(_playheadsStorageKey, jsonEncode(_playheads));
        }
      }
    } catch (_) {
      // Non-critical offline fallback
    }
  }

  Future<void> _onSyncStateChanged() async {
    if (UserSyncService.instance.activeUserId == null) {
      if (_history.isNotEmpty || _playheads.isNotEmpty) {
        _history = [];
        _playheads = {};
        notifyListeners();
      }
      return;
    }
    final remote = UserSyncService.instance.remoteState;
    if (remote == null) return;
    final pending = UserSyncService.instance.pendingOps;
    var changed = false;

    final remoteHistory = remote['videoHistory'];
    if (remoteHistory is List) {
      final tombstones = (remote['videoHistoryTombstones'] as Map?) ?? {};
      final existingIds = _history.map((v) => v.id).toSet();
      final next = _history.where((v) {
        final op = pending['video_history:${v.id}'];
        if (op?.isDeleted == true) return false;
        if (tombstones.containsKey(v.id) && op == null) return false;
        return true;
      }).toList();
      final nextIds = next.map((v) => v.id).toSet();
      for (final item in remoteHistory.whereType<Map>()) {
        final videoMap = item['video'] is Map
            ? Map<String, dynamic>.from(item['video'] as Map)
            : Map<String, dynamic>.from(item);
        final video = Video.fromJson(videoMap);
        final op = pending['video_history:${video.id}'];
        if (video.id.isNotEmpty &&
            op?.isDeleted != true &&
            !nextIds.contains(video.id)) {
          nextIds.add(video.id);
          next.add(video);
          changed = true;
        }
      }
      if (next.length != existingIds.length || changed) {
        _history = next.take(100).toList();
        changed = true;
      }
    }

    final remotePlayheads = remote['videoPlayheads'];
    if (remotePlayheads is Map) {
      for (final entry in remotePlayheads.entries) {
        final vid = entry.key.toString();
        if (entry.value is Map && !pending.containsKey('video_playhead:$vid')) {
          final map = Map<String, dynamic>.from(entry.value as Map);
          final remoteUpdated = (map['updatedAt'] as num?)?.toInt() ?? 0;
          final localUpdated = (_playheads[vid]?['updatedAt'] as num?)?.toInt() ?? 0;
          if (remoteUpdated >= localUpdated) {
            _playheads[vid] = map;
          }
        }
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_playheadsStorageKey, jsonEncode(_playheads));
      } catch (_) {}
    }

    if (changed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _historyStorageKey,
          jsonEncode(_history.map((v) => v.toJson()).toList()),
        );
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> _persistHistoryItemToSync(Video video, {bool isDeleted = false}) async {
    unawaited(
      UserSyncService.instance.enqueueWatchItem(
        itemType: 'video_history',
        itemId: video.id,
        positionSeconds: (_playheads[video.id]?['positionSeconds'] as num?)?.toInt() ?? 0,
        isDeleted: isDeleted,
      ),
    );
  }

  Future<void> addToHistory(Video video) async {
    // Remove if already present so it moves to index 0 (most recent)
    _history.removeWhere((v) => v.id == video.id);
    _history.insert(0, video);

    // Limit history to 100 entries
    if (_history.length > 100) {
      _history = _history.sublist(0, 100);
    }

    notifyListeners();

    // 1. Save to local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_history.map((v) => v.toJson()).toList());
      await prefs.setString(_historyStorageKey, raw);
    } catch (e) {
      debugPrint('Error persisting watch history: $e');
    }

    // 2. Enqueue atomic sync op
    await _persistHistoryItemToSync(video, isDeleted: false);
  }

  Future<void> removeFromHistory(String videoId) async {
    _history.removeWhere((v) => v.id == videoId);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_history.map((v) => v.toJson()).toList());
      await prefs.setString(_historyStorageKey, raw);
    } catch (e) {
      debugPrint('Error updating watch history: $e');
    }

    unawaited(
      UserSyncService.instance.enqueueWatchItem(
        itemType: 'video_history',
        itemId: videoId,
        isDeleted: true,
      ),
    );
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyStorageKey);
    } catch (e) {
      debugPrint('Error clearing watch history: $e');
    }

    try {
      await _apiClient.dio.delete('/user/history');
    } catch (_) {}
  }

  Future<void> fetchUserData() async {
    try {
      final resPlaylists = await _apiClient.dio.get('/user/playlists');
      if (resPlaylists.statusCode == 200 && resPlaylists.data != null) {
        final dynamic raw = resPlaylists.data;
        final List<dynamic> list = raw is List ? raw : raw['playlists'] ?? [];
        _playlists = list.map((p) => Playlist.fromJson(p)).toList();
      }
    } catch (_) {}

    try {
      final resHistory = await _apiClient.dio.get('/user/history');
      if (resHistory.statusCode == 200 && resHistory.data != null) {
        final dynamic raw = resHistory.data;
        final List<dynamic> list = raw is List ? raw : raw['history'] ?? [];
        if (list.isNotEmpty) {
          final remoteHistory = list.map((v) => Video.fromJson(v)).toList();
          // Merge remote history without duplicating
          final ids = _history.map((v) => v.id).toSet();
          for (final v in remoteHistory) {
            if (!ids.contains(v.id)) {
              _history.add(v);
            }
          }
        }
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> fetchRegisteredUsers([String? search]) async {
    _isLoadingUsers = true;
    notifyListeners();

    try {
      final Map<String, dynamic> params = {};
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }

      final res = await _apiClient.dio.get('/users', queryParameters: params);
      if (res.statusCode == 200 && res.data != null) {
        final List<dynamic> list = res.data is List ? res.data : [];
        _registeredUsers = list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error fetching registered users: $e');
    } finally {
      _isLoadingUsers = false;
      notifyListeners();
    }
  }

  Future<bool> toggleBlockUser(String userId) async {
    try {
      final res = await _apiClient.dio.post('/users/$userId/toggle-block');
      if (res.statusCode == 200 || res.statusCode == 201) {
        final updatedUser = res.data;
        final idx = _registeredUsers.indexWhere((u) => u['id'] == userId);
        if (idx != -1) {
          _registeredUsers[idx] = updatedUser;
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error toggling block user: $e');
    }
    return false;
  }

  Future<bool> createPlaylist(String title, String? description) async {
    try {
      final response = await _apiClient.dio.post(
        '/user/playlists',
        data: {'title': title, 'description': description},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final newPlaylist = Playlist.fromJson(response.data);
        _playlists.add(newPlaylist);
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  static const String _videoPositionPrefix = 'video_playhead_';

  /// Saves the last known playback position in seconds for [videoId].
  Future<void> saveVideoPosition(String videoId, double seconds) async {
    if (videoId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('$_videoPositionPrefix$videoId', seconds);

      _playheads[videoId] = {
        'positionSeconds': seconds.round(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      if (_playheads.length > 200) {
        final sorted = _playheads.entries.toList()
          ..sort((a, b) => ((b.value['updatedAt'] as num?)?.toInt() ?? 0)
              .compareTo((a.value['updatedAt'] as num?)?.toInt() ?? 0));
        _playheads = Map.fromEntries(sorted.take(200));
      }
      await prefs.setString(_playheadsStorageKey, jsonEncode(_playheads));

      unawaited(
        UserSyncService.instance.enqueueWatchItem(
          itemType: 'video_playhead',
          itemId: videoId,
          positionSeconds: seconds.round(),
          isDeleted: false,
        ),
      );
    } catch (_) {}
  }

  /// Gets the last known playback position in seconds for [videoId], defaulting to 0.0.
  Future<double> getVideoPosition(String videoId) async {
    if (videoId.isEmpty) return 0.0;
    try {
      final synced = (_playheads[videoId]?['positionSeconds'] as num?)?.toDouble();
      if (synced != null && synced > 0) return synced;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('$_videoPositionPrefix$videoId') ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<bool> removeUser(String userId) async {
    try {
      final res = await _apiClient.dio.delete('/users/$userId');
      if (res.statusCode == 200 || res.statusCode == 204) {
        _registeredUsers.removeWhere((u) => u['id'] == userId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error removing user: $e');
    }
    return false;
  }
}
