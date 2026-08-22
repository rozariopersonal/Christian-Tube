import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../shared/ui/search_video_card.dart';

class VideoSearchDelegate extends SearchDelegate<Video?> {
  final ApiClient _apiClient = ApiClient();

  @override
  String get searchFieldLabel => 'Search Christian videos...';

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
    final suggestions = [
      'Worship Songs',
      'Daily Sermon',
      'Bible Study',
      'Gospel Tamil',
      'Gospel Telugu',
      'Gospel Hindi',
      'Christian Testimonies',
    ].where((s) => s.toLowerCase().contains(query.toLowerCase())).toList();

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
      final response = await _apiClient.dio.get(
        '/api/search',
        queryParameters: {'q': query},
      );
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : response.data['videos'] ?? [];
        return list.map((v) => Video.fromJson(v)).toList();
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
    return [];
  }
}
