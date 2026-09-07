import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';
import 'audio_download_all_button.dart';

/// Series detail header: cover art, title/speaker/description, and the
/// Play All + Download All action row.
class AudioSeriesHeader extends StatelessWidget {
  final AudioSeries? series;
  final VoidCallback onPlayAll;

  const AudioSeriesHeader({
    super.key,
    required this.series,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final coverUrl = series?.coverUrl;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 100,
                  height: 100,
                  color: tokens.surfaceVariant,
                  child: coverUrl != null && coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.album,
                            size: 40,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.album,
                          size: 40,
                          color: theme.colorScheme.primary,
                        ),
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series?.title ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: tokens.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${series?.speaker} • ${series?.trackCount ?? 0} Tracks',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      series?.description ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (series != null && series!.tracks.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onPlayAll,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: Text('Play All (${series!.tracks.length} Tracks)'),
                  ),
                ),
                const SizedBox(width: 10),
                AudioDownloadAllButton(tracks: series!.tracks),
              ],
            ),
          ],
        ],
      ),
    );
  }
}