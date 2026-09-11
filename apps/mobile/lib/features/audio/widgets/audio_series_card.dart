import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';

/// Compact cover card for a sermon series, used inside the carousel and the
/// category grid. Tapping invokes [onTap].
class AudioSeriesCard extends StatelessWidget {
  final AudioSeries series;
  final VoidCallback onTap;

  const AudioSeriesCard({
    super.key,
    required this.series,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                color: tokens.surfaceVariant,
                child: series.coverUrl != null && series.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: series.coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _FallbackIcon(theme: theme),
                      )
                    : _FallbackIcon(theme: theme),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
          Text(
            '${series.trackCount} Tracks • ${series.category}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final ThemeData theme;

  const _FallbackIcon({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.headphones,
        size: 40,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
