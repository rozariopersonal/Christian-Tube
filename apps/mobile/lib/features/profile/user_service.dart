import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/playlist.dart';
import '../../core/models/video.dart';

class UserService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

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
        _history = list.map((v) => Video.fromJson(v)).toList();
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
}
