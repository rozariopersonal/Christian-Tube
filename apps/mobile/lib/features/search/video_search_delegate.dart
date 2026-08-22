import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../shared/ui/search_video_card.dart';
import '../../core/config/app_config.dart';

class VideoSearchDelegate extends SearchDelegate<Video?> {
  final ApiClient _apiClient = ApiClient();

  @override
  String get searchFieldLabel => 'Search ${AppConfig.appName} videos...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(child: Text('Type a keyword to search'));
    }

    return FutureBuilder<List<Video>>(
      future: _searchVideos(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final videos = snapshot.data ?? [];
        if (videos.isEmpty) {
          return const Center(child: Text('No videos found.'));
        }
        return ListView.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) => SearchVideoCard(video: videos[index]),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = AppConfig.defaultCategories
        .where((s) => s != 'All' && s.toLowerCase().contains(query.toLowerCase()))
        .toList();

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return ListTile(
          leading: const Icon(Icons.search, size: 20),
          title: Text(suggestion),
          onTap: () {
            query = suggestion;
            showResults(context);
          },
        );
      },
    );
  }

  Future<List<Video>> _searchVideos(String query) async {
    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get(
          '/api/search',
          queryParameters: {'q': query},
        );
      } catch (_) {
        response = await _apiClient.dio.get(
          '/videos',
          queryParameters: {'search': query},
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        return list.map((v) => Video.fromJson(v as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
    return [];
  }
}
