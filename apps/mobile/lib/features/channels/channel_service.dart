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
      final response = await _apiClient.dio.get('/channels');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : response.data['channels'] ?? [];
        _channels = list.map((c) => Channel.fromJson(c)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching channels: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitChannelRequest(ChannelRequest request) async {
    try {
      final response = await _apiClient.dio.post(
        '/channels/request',
        data: request.toJson(),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Error submitting channel request: $e');
      return false;
    }
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
