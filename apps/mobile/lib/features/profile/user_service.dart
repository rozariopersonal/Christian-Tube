import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/playlist.dart';
import '../../core/models/video.dart';

class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal() {
    loadLocalHistory();
  }

  final ApiClient _apiClient = ApiClient();
  static const String _historyStorageKey = 'user_watch_history_v1';

  List<Playlist> _playlists = [];
  List<Video> _history = [];
  final List<Channel> _subscriptions = [];
  List<Map<String, dynamic>> _registeredUsers = [];
  bool _isLoadingUsers = false;

  List<Playlist> get playlists => _playlists;
  List<Video> get history => _history;
  List<Channel> get subscriptions => _subscriptions;
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
    } catch (e) {
      debugPrint('Error loading local watch history: $e');
    }
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

    // 2. Sync with backend if available
    try {
      await _apiClient.dio.post('/user/history', data: {'videoId': video.id});
    } catch (_) {}
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

    try {
      await _apiClient.dio.delete('/user/history/$videoId');
    } catch (_) {}
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

      // Best-effort sync with backend if online
      final userJson = prefs.getString('current_user');
      String? email;
      if (userJson != null && userJson.isNotEmpty) {
        try {
          email = jsonDecode(userJson)['email'] as String?;
        } catch (_) {}
      }

      await _apiClient.dio.post('/user/playback', data: {
        'userEmail': email,
        'trackId': videoId,
        'mediaType': 'video',
        'positionSeconds': seconds.round(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Gets the last known playback position in seconds for [videoId], defaulting to 0.0.
  Future<double> getVideoPosition(String videoId) async {
    if (videoId.isEmpty) return 0.0;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('$_videoPositionPrefix$videoId') ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}
