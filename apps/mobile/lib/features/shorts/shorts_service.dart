import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';

class ShortsService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  List<Short> _shorts = [];
  bool _isLoading = false;

  List<Short> get shorts => _shorts;
  bool get isLoading => _isLoading;

  Future<void> fetchShorts() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.dio.get('/shorts/feed');
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['shorts'] ?? raw['data'] ?? []);
        _shorts = list.whereType<Map<String, dynamic>>().map((s) => Short.fromJson(s)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching shorts: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
