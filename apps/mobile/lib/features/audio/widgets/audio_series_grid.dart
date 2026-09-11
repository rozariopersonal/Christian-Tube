import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_language_meta.dart';
import '../controllers/audio_library_controller.dart';
import '../models/audio_series.dart';
import 'audio_series_card.dart';

/// Filtered series grid for the selected category/language in the Audio
/// Library, with a header summarizing the current filter set.
class AudioSeriesGrid extends StatelessWidget {
  final AudioLibraryViewState state;
  final VoidCallback onReset;
  final ValueChanged<AudioSeries> onOpenSeries;

  const AudioSeriesGrid({
    super.key,
    required this.state,
    required this.onReset,
    required this.onOpenSeries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final filtered = state.filteredSeries;
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

    final headerTitle = state.selectedCategory == 'All'
        ? 'All Series (${filtered.length}$langSuffix)'
        : '${state.selectedCategory} (${filtered.length}$langSuffix)';

    final showReset = state.selectedCategory != 'All' || !isAllLang;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showReset)
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
                TextButton(
                  onPressed: onReset,
                  child: const Text('Reset'),
                ),
              ],
            )
          else
            Text(
              headerTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'No series found for the selected filter.',
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
                  itemCount: filtered.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) {
                    final series = filtered[index];
                    return AudioSeriesCard(
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
