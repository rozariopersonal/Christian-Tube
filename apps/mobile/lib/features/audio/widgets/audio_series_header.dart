import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';
import 'audio_download_all_button.dart';

/// Series detail header: cover art, title/speaker/description, and the
/// Play All + Download All action row.
///
/// Design: larger cover (120px) with shadow, speaker chip, gradient Play All
/// button, and a "Show more/less" expandable description.
class AudioSeriesHeader extends StatefulWidget {
  final AudioSeries? series;
  final VoidCallback onPlayAll;

  const AudioSeriesHeader({
    super.key,
    required this.series,
    required this.onPlayAll,
  });

  @override
  State<AudioSeriesHeader> createState() => _AudioSeriesHeaderState();
}

class _AudioSeriesHeaderState extends State<AudioSeriesHeader> {
  bool _descExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final series = widget.series;
    final coverUrl = series?.coverUrl;
    final hasDescription =
        series?.description != null && series!.description.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover art ΓÇö 120├ù120 with shadow
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(
                          alpha: tokens.isDark ? 0.4 : 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 120,
                    height: 120,
                    color: tokens.surfaceVariant,
                    child: coverUrl != null && coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(
                              Icons.album,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.album,
                            size: 48,
                            color: theme.colorScheme.primary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Meta info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series?.title ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: tokens.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Speaker chip
                    if (series?.speaker != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.4),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 13,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                series!.speaker,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),

                    // Track count with music icon
                    Row(
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          size: 14,
                          color: tokens.onSurfaceMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${series?.trackCount ?? 0} Tracks',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.onSurfaceMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Expandable description
          if (hasDescription) ...[
            const SizedBox(height: 16),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              firstChild: Text(
                series!.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                  height: 1.5,
                ),
              ),
              secondChild: Text(
                series!.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                  height: 1.5,
                ),
              ),
              crossFadeState: _descExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
            ),
            GestureDetector(
              onTap: () => setState(() => _descExpanded = !_descExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _descExpanded ? 'Show less' : 'Show more',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],

          // Play All + Download All actions
          if (series != null && series.tracks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.75),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.onPlayAll,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label:
                          Text('Play All (${series.tracks.length} Tracks)'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AudioDownloadAllButton(tracks: series.tracks),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
