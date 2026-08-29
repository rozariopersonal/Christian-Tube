import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/formatters.dart';

class ShortsSearchDelegate extends SearchDelegate<Short?> {
  final ApiClient _apiClient = ApiClient();

  @override
  String get searchFieldLabel => 'Search ${AppConfig.appName} Shorts...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: tokens.background,
        iconTheme: IconThemeData(color: tokens.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 16),
        border: InputBorder.none,
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: TextStyle(color: tokens.onSurface, fontSize: 16),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: Icon(Icons.clear, color: context.tokens.onSurfaceMuted),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back_ios_new, color: context.tokens.onSurface, size: 20),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return Center(
        child: Text(
          'Type keywords to search Shorts',
          style: TextStyle(color: context.tokens.onSurfaceMuted),
        ),
      );
    }

    return Container(
      color: context.tokens.background,
      child: FutureBuilder<List<Short>>(
        future: _searchShorts(query.trim()),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: context.tokens.accent),
            );
          }
          final shorts = snapshot.data ?? [];
          if (shorts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 56, color: context.tokens.onSurfaceDisabled),
                  const SizedBox(height: 12),
                  Text(
                    'No Shorts found for "$query"',
                    style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 15),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            itemCount: shorts.length,
            separatorBuilder: (_, __) => Divider(color: context.tokens.surfaceBorder, height: 16),
            itemBuilder: (context, index) {
              final short = shorts[index];
              final durSec = short.durationSeconds > 0
                  ? short.durationSeconds
                  : Short.parseDurationInSeconds(short.duration);

              return InkWell(
                onTap: () => close(context, short),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      // Thumbnail with Duration
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            CachedNetworkImage(
                              imageUrl: short.thumbnailUrl,
                              width: 80,
                              height: 120,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: context.tokens.surface),
                              errorWidget: (_, __, ___) => Container(
                                width: 80,
                                height: 120,
                                color: context.tokens.surface,
                                child: Icon(Icons.movie, color: context.tokens.onSurfaceDisabled),
                              ),
                            ),
                            if (durSec > 0)
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    Formatters.formatDuration(Duration(seconds: durSec)),
                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              short.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.tokens.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              short.channelTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              short.viewCount > 0
                                  ? '${Formatters.formatViews(short.viewCount)} views'
                                  : 'Short',
                              style: TextStyle(
                                color: context.tokens.onSurfaceMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.play_arrow_rounded, color: context.tokens.accent, size: 28),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(
      color: context.tokens.background,
      child: Center(
        child: Text(
          'Search Christian Shorts by title, preacher, or topic',
          style: TextStyle(color: context.tokens.onSurfaceDisabled, fontSize: 13),
        ),
      ),
    );
  }

  Future<List<Short>> _searchShorts(String searchQuery) async {
    try {
      final response = await _apiClient.dio.get(
        '/videos',
        queryParameters: {
          'type': 'SHORT',
          'search': searchQuery,
          'limit': 50,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        return list
            .whereType<Map<String, dynamic>>()
            .map((s) => Short.fromJson(s))
            .where((s) => s.durationSeconds <= 180 || s.type == 'SHORT')
            .toList();
      }
    } catch (e) {
      debugPrint('Error searching shorts: $e');
    }
    return [];
  }
}
