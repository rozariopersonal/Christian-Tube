import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/channel_request.dart';

class ChannelService extends ChangeNotifier {
  static final ChannelService _instance = ChannelService._internal();
  factory ChannelService() => _instance;
  ChannelService._internal() {
    loadSubscriptions();
  }

  final ApiClient _apiClient = ApiClient();
  List<Channel> _channels = [];
  List<Map<String, dynamic>> _channelRequests = [];
  bool _isLoading = false;
  bool _isLoadingRequests = false;
  Set<String> _subscribedIds = {};

  List<Channel> get channels => _channels;
  List<Map<String, dynamic>> get channelRequests => _channelRequests;
  bool get isLoading => _isLoading;
  bool get isLoadingRequests => _isLoadingRequests;
  Set<String> get subscribedChannelIds => _subscribedIds;

  bool isSubscribed(String channelId) => _subscribedIds.contains(channelId);

  Future<void> loadSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('subscribed_channel_ids') ?? [];
      _subscribedIds = list.toSet();
      _syncSubscriptionStatus();
      notifyListeners();
    } catch (_) {}
  }

  void _syncSubscriptionStatus() {
    for (int i = 0; i < _channels.length; i++) {
      final ch = _channels[i];
      if (_subscribedIds.contains(ch.id) != ch.isSubscribed) {
        _channels[i] = ch.copyWith(isSubscribed: _subscribedIds.contains(ch.id));
      }
    }
  }

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

        _syncSubscriptionStatus();
      }
    } catch (e) {
      debugPrint('Error fetching channels: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchRequests() async {
    _isLoadingRequests = true;
    notifyListeners();

    try {
      final response = await _apiClient.dio.get('/channels/requests');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : [];
        _channelRequests = list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error fetching channel requests: $e');
    } finally {
      _isLoadingRequests = false;
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
        final dynamic list = response.data is List ? response.data : [];
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
    String? adminEmail,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/channels',
        data: {
          'channelUrl': channelUrl,
          'name': name,
          'category': category,
          'language': language,
          'adminEmail': adminEmail,
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
        _subscribedIds.remove(channelId);
        _saveSubscriptions();
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
        await fetchRequests();
        return true;
      }
    } catch (e) {
      debugPrint('Error submitting channel request: $e');
    }
    return false;
  }

  Future<bool> approveRequest(String requestId, [String? adminEmail]) async {
    try {
      final response = await _apiClient.dio.post(
        '/channels/requests/$requestId/approve',
        data: {'adminEmail': adminEmail},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchChannels();
        await fetchRequests();
        return true;
      }
    } catch (e) {
      debugPrint('Error approving channel request: $e');
    }
    return false;
  }

  Future<bool> rejectRequest(String requestId, [String? reason]) async {
    try {
      final response = await _apiClient.dio.post(
        '/channels/requests/$requestId/reject',
        data: {'reason': reason},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchRequests();
        return true;
      }
    } catch (e) {
      debugPrint('Error rejecting channel request: $e');
    }
    return false;
  }

  Future<void> _saveSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('subscribed_channel_ids', _subscribedIds.toList());
    } catch (_) {}
  }

  void toggleSubscribe(String channelId) {
    if (_subscribedIds.contains(channelId)) {
      _subscribedIds.remove(channelId);
    } else {
      _subscribedIds.add(channelId);
    }

    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index != -1) {
      final ch = _channels[index];
      _channels[index] = ch.copyWith(isSubscribed: _subscribedIds.contains(channelId));
    }

    _saveSubscriptions();
    notifyListeners();
  }
}
