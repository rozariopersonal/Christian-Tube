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
      langSuffix = ' ΓÇó ${meta.englishName}';
    } else {
      langSuffix = ' ΓÇó ${state.selectedLanguages.length} Languages';
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Accent bar
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
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
                GestureDetector(
                  onTap: onReset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Reset',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
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
                    maxCrossAxisExtent: 175,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
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
