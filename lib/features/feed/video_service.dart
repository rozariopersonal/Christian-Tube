import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';

class VideoService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

  List<Video> _videos = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedCategory = 'All';

  List<Video> get videos => _videos;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedCategory => _selectedCategory;

  final List<String> categories = const [
    'All',
    'Worship',
    'Sermons',
    'Testimonies',
    'Bible Study',
    'Youth',
    'Gospel Music',
    'Kids',
  ];

  Future<void> fetchFeed({bool refresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.dio.get(
        '/api/videos',
        queryParameters: {
          if (_selectedCategory != 'All') 'category': _selectedCategory,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : response.data['videos'] ?? [];
        _videos = list.map((v) => Video.fromJson(v)).toList();
      }
    } catch (e) {
      debugPrint('Error loading video feed: $e');
      _errorMessage = 'Failed to load videos. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
    fetchFeed(refresh: true);
  }
}
