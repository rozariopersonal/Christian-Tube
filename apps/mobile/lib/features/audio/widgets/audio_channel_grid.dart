import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_language_meta.dart';
import '../controllers/audio_library_controller.dart';
import '../models/audio_series.dart';

/// Grid specifically designed for YouTube Channels, featuring large circular
/// avatars, bold channel names, and audio counts.
class AudioChannelGrid extends StatelessWidget {
  final AudioLibraryViewState state;
  final VoidCallback onReset;
  final ValueChanged<AudioSeries> onOpenSeries;
  final ValueChanged<AudioChannelSort> onChannelSortChanged;

  const AudioChannelGrid({
    super.key,
    required this.state,
    required this.onReset,
    required this.onOpenSeries,
    required this.onChannelSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final sorted = state.channelSortedSeries;
    final isAllLang = state.isAllLanguagesSelected;
    final String langSuffix;
    if (isAllLang) {
      langSuffix = '';
    } else if (state.selectedLanguages.length == 1) {
      final meta = BookLanguageMeta.fromCode(state.selectedLanguages.first);
      langSuffix = ' • ${meta.englishName}';
    } else {
      langSuffix = ' • ${state.selectedLanguages.length} Languages';
    }

    final headerTitle =
        'YouTube Channels (${state.filteredSeries.length}$langSuffix)';
    final showReset = state.selectedCategory != 'All' || !isAllLang;

    return MaxWidthBox(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  headerTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.onSurface,
                  ),
                ),
              ),
              if (showReset)
                TextButton(
                  onPressed: onReset,
                  child: const Text('Reset'),
                ),
              PopupMenuButton<AudioChannelSort>(
                initialValue: state.channelSort,
                tooltip: 'Sort channels',
                icon: Icon(Icons.sort, color: tokens.onSurfaceMuted),
                onSelected: onChannelSortChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: AudioChannelSort.mostTracks,
                    child: Text('Most tracks'),
                  ),
                  PopupMenuItem(
                    value: AudioChannelSort.name,
                    child: Text('A–Z'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (sorted.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'No channels found for the selected filter.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sorted.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) {
                    final series = sorted[index];
                    return _AudioChannelCard(
                      series: series,
                      onTap: () => onOpenSeries(series),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AudioChannelCard extends StatelessWidget {
  final AudioSeries series;
  final VoidCallback onTap;

  const _AudioChannelCard({
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

    // Using a subtle gradient/glassmorphic surface for the card
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: tokens.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tokens.surfaceBorder.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Circular Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.surface,
                    border: Border.all(
                      color: tokens.surfaceBorder,
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: series.coverUrl != null && series.coverUrl!.isNotEmpty
                      ? Image.network(
                          series.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallbackIcon(tokens),
                        )
                      : _buildFallbackIcon(tokens),
                ),
                const SizedBox(height: 8),
                
                // Channel Name
                Flexible(
                  child: Text(
                    series.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                
                // Track Count Subtitle
                Text(
                  '${series.trackCount} Tracks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(AppTokens tokens) {
    return Icon(
      Icons.video_library_rounded,
      size: 32,
      color: tokens.onSurfaceMuted.withValues(alpha: 0.5),
    );
  }
}
