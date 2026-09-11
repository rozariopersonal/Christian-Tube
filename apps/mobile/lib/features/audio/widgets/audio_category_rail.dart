import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';
import 'audio_series_card.dart';

/// Horizontal rail of audio series for a specific category or collection.
class AudioCategoryRail extends StatelessWidget {
  final String title;
  final List<AudioSeries> seriesList;
  final VoidCallback onSeeAll;
  final ValueChanged<AudioSeries> onTapSeries;

  const AudioCategoryRail({
    super.key,
    required this.title,
    required this.seriesList,
    required this.onSeeAll,
    required this.onTapSeries,
  });

  @override
  Widget build(BuildContext context) {
    if (seriesList.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tokens.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${seriesList.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onSeeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See All',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 195,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: seriesList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final series = seriesList[index];
              return SizedBox(
                width: 135,
                child: AudioSeriesCard(
                  series: series,
                  onTap: () => onTapSeries(series),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
