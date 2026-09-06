import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';

/// Search delegate for finding audio series across the catalog.
class AudioSearchDelegate extends SearchDelegate<AudioSeries?> {
  final List<AudioSeries> allSeries;

  AudioSearchDelegate(this.allSeries);

  @override
  String get searchFieldLabel => 'Search sermons, series, topics...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        elevation: 0,
        iconTheme: IconThemeData(color: tokens.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: tokens.onSurfaceMuted,
        ),
        border: InputBorder.none,
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: theme.textTheme.bodyLarge?.copyWith(
          color: tokens.onSurface,
        ),
      ),
    );
  }

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
    return _buildList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final clean = query.trim().toLowerCase();
    final results = clean.isEmpty
        ? allSeries.take(15).toList()
        : allSeries.where((s) {
            return s.title.toLowerCase().contains(clean) ||
                s.category.toLowerCase().contains(clean) ||
                s.speaker.toLowerCase().contains(clean) ||
                s.description.toLowerCase().contains(clean);
          }).toList();

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: tokens.onSurfaceMuted),
            const SizedBox(height: 12),
            Text(
              'No audio series found for "$query"',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: tokens.background,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: results.length,
        separatorBuilder: (_, __) => Divider(
          color: tokens.surfaceBorder,
          height: 1,
        ),
        itemBuilder: (context, index) {
          final s = results[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: tokens.surfaceVariant,
                child: s.coverUrl != null && s.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: s.coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.headphones,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.headphones,
                        color: theme.colorScheme.primary,
                      ),
              ),
            ),
            title: Text(
              s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            subtitle: Text(
              '${s.category} • ${s.trackCount} Tracks • ${s.speaker}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
            onTap: () {
              close(context, s);
              context.push('/audio/series/${s.id}', extra: s);
            },
          );
        },
      ),
    );
  }
}
