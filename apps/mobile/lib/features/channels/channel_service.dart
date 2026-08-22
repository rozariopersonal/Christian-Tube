import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/channel_request.dart';

class ChannelService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  List<Channel> _channels = [];
  bool _isLoading = false;

  List<Channel> get channels => _channels;
  bool get isLoading => _isLoading;

  Future<void> fetchChannels() async {
    _isLoading = true;
    notifyListeners();

    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get('/api/channels');
      } catch (_) {
        response = await _apiClient.dio.get('/channels');
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['channels'] ?? raw['data'] ?? []);
        _channels = list
            .whereType<Map<String, dynamic>>()
            .map((c) => Channel.fromJson(c))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching channels: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> searchYouTubeChannels(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get(
          '/api/channels/search-youtube',
          queryParameters: {'q': query},
        );
      } catch (_) {
        response = await _apiClient.dio.get(
          '/channels/search-youtube',
          queryParameters: {'q': query},
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : [];
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error searching YouTube channels: $e');
    }
    return [];
  }

  Future<bool> addChannel({
    required String channelUrl,
    String? name,
    String? category,
    String? language,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/channels',
        data: {
          'channelUrl': channelUrl,
          'name': name,
          'category': category,
          'language': language,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchChannels();
        return true;
      }
    } catch (e) {
      debugPrint('Error adding channel: $e');
    }
    return false;
  }

  Future<bool> removeChannel(String channelId) async {
    try {
      final response = await _apiClient.dio.delete('/channels/$channelId');
      if (response.statusCode == 200 || response.statusCode == 204) {
        _channels.removeWhere((c) => c.id == channelId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error removing channel: $e');
    }
    return false;
  }

  Future<bool> submitChannelRequest(ChannelRequest request) async {
    try {
      final response = await _apiClient.dio.post(
        '/channels/request',
        data: request.toJson(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchChannels();
        return true;
      }
    } catch (e) {
      debugPrint('Error submitting channel request: $e');
    }
    return false;
  }

  void toggleSubscribe(String channelId) {
    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index != -1) {
      final ch = _channels[index];
      _channels[index] = ch.copyWith(isSubscribed: !ch.isSubscribed);
      notifyListeners();
    }
  }
}
