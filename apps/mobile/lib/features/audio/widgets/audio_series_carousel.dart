import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';
import 'audio_series_card.dart';

/// Horizontal "Featured Series" carousel shown on the Audio Library home view.
class AudioSeriesCarousel extends StatelessWidget {
  final List<AudioSeries> seriesList;
  final ValueChanged<AudioSeries> onTapSeries;

  const AudioSeriesCarousel({
    super.key,
    required this.seriesList,
    required this.onTapSeries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final featured = seriesList.take(8).toList();
    if (featured.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Featured Series',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final series = featured[index];
              return AudioSeriesCard(
                series: series,
                onTap: () => onTapSeries(series),
              );
            },
          ),
        ),
      ],
    );
  }
}