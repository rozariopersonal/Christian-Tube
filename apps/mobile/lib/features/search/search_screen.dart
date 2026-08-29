import 'package:flutter/material.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../core/models/short.dart';
import '../../shared/ui/search_video_card.dart';
import '../../core/config/app_config.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiClient _apiClient = ApiClient();
  List<Video> _searchResults = [];
  bool _isLoading = false;

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get(
          '/api/search',
          queryParameters: {'q': query, 'type': 'VIDEO'},
        );
      } catch (_) {
        response = await _apiClient.dio.get(
          '/videos',
          queryParameters: {'search': query, 'type': 'VIDEO'},
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        setState(() {
          _searchResults = list
              .whereType<Map<String, dynamic>>()
              .where((json) => !Short.isShort(json))
              .map((v) => Video.fromJson(v))
              .where((v) => v.type != 'SHORT')
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search ${AppConfig.appName}...',
            border: InputBorder.none,
          ),
          onSubmitted: _performSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchResults = []);
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _performSearch(_searchController.text),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 64, color: context.tokens.onSurfaceDisabled),
                      const SizedBox(height: 12),
                      Text('Search ${AppConfig.appName} videos, lessons, and clips'),
                    ],
                  ),
                )
              : MaxWidthBox(
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      return SearchVideoCard(video: _searchResults[index]);
                    },
                  ),
                ),
    );
  }
}
