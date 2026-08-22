import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/playlist.dart';
import '../../core/models/video.dart';

class UserService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

  List<Playlist> _playlists = [];
  List<Video> _history = [];
  List<Channel> _subscriptions = [];

  List<Playlist> get playlists => _playlists;
  List<Video> get history => _history;
  List<Channel> get subscriptions => _subscriptions;

  Future<void> fetchUserData() async {
    try {
      final resPlaylists = await _apiClient.dio.get('/user/playlists');
      if (resPlaylists.statusCode == 200 && resPlaylists.data != null) {
        final List<dynamic> list = resPlaylists.data is List ? resPlaylists.data : resPlaylists.data['playlists'] ?? [];
        _playlists = list.map((p) => Playlist.fromJson(p)).toList();
      }
    } catch (_) {}

    try {
      final resHistory = await _apiClient.dio.get('/user/history');
      if (resHistory.statusCode == 200 && resHistory.data != null) {
        final List<dynamic> list = resHistory.data is List ? resHistory.data : resHistory.data['history'] ?? [];
        _history = list.map((v) => Video.fromJson(v)).toList();
      }
    } catch (_) {}

    notifyListeners();
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
