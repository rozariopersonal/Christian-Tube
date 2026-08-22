import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';

class ShortsSearchDelegate extends SearchDelegate<Short?> {
  final ApiClient _apiClient = ApiClient();

  @override
  String get searchFieldLabel => 'Search Christian Shorts...';

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
    return FutureBuilder<List<Short>>(
      future: _searchShorts(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final shorts = snapshot.data ?? [];
        if (shorts.isEmpty) {
          return const Center(child: Text('No shorts found.'));
        }
        return ListView.builder(
          itemCount: shorts.length,
          itemBuilder: (context, index) {
            final short = shorts[index];
            return ListTile(
              leading: Image.network(short.thumbnailUrl, width: 50, fit: BoxFit.cover),
              title: Text(short.title, maxLines: 1),
              subtitle: Text(short.channelTitle),
              onTap: () => close(context, short),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container();
  }

  Future<List<Short>> _searchShorts(String query) async {
    try {
      final response = await _apiClient.dio.get(
        '/shorts/search',
        queryParameters: {'q': query},
      );
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : response.data['shorts'] ?? [];
        return list.map((s) => Short.fromJson(s)).toList();
      }
    } catch (_) {}
    return [];
  }
}
