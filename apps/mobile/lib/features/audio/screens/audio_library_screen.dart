import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_dropdown.dart';
import '../controllers/audio_library_controller.dart';
import '../models/audio_series.dart';
import '../widgets/audio_category_chips.dart';
import '../widgets/audio_continue_listening_card.dart';
import '../widgets/audio_search_delegate.dart';
import '../widgets/audio_series_carousel.dart';
import '../widgets/audio_series_grid.dart';
import '../widgets/audio_topics_grid.dart';

/// Main Audio tab screen — browse sermon series, continue listening, explore
/// topics, and filter by category and language. Thin assembler: all behavior
/// lives in [AudioLibraryController], the widgets are presentational.
class AudioLibraryScreen extends StatefulWidget {
  final LibraryLanguagesController? langController;

  const AudioLibraryScreen({super.key, this.langController});

  @override
  State<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends State<AudioLibraryScreen> {
  late final AudioLibraryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AudioLibraryController(
      langController: widget.langController,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;

        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.background,
            elevation: 0,
            title: Text(
              'Audio Library',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                color: tokens.onSurface,
                tooltip: 'Search Audio',
                onPressed: () {
                  showSearch(
                    context: context,
                    delegate: AudioSearchDelegate(state.seriesList),
                  );
                },
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _controller.loadData(forceRefresh: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: MaxWidthBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: LanguageDropdown(
                              selectedLanguages:
                                  _controller.languageController.state.selectedLanguages,
                              availableLanguages: state.availableLanguages,
                              itemCounts: state.languageTrackCounts,
                              onLanguagesSelected:
                                  _controller.languageController.selectLanguages,
                              itemNoun: 'tracks',
                              headerTitle: 'Audio by Language',
                            ),
                          ),
                          const SizedBox(height: 14),

                          AudioCategoryChips(
                            categories: AudioLibraryController.categories,
                            selected: state.selectedCategory,
                            onSelected: _controller.selectCategory,
                          ),
                          const SizedBox(height: 16),

                          if (state.selectedCategory == 'All' &&
                              state.isAllLanguagesSelected) ...[
                            AudioSeriesCarousel(
                              seriesList: state.seriesList,
                              onTapSeries: _openSeries,
                            ),
                            const SizedBox(height: 24),
                          ],

                          if (state.lastPlayedTrack != null) ...[
                            AudioContinueListeningCard(
                              track: state.lastPlayedTrack!,
                              savedSeconds: state.lastPlayedSeconds,
                            ),
                            const SizedBox(height: 24),
                          ],

                          if (state.selectedCategory == 'All' &&
                              state.isAllLanguagesSelected) ...[
                            AudioTopicsGrid(
                              onTopicSelected: _controller.selectCategory,
                            ),
                            const SizedBox(height: 24),
                          ],

                          AudioSeriesGrid(
                            state: state,
                            onReset: _controller.resetFilters,
                            onOpenSeries: _openSeries,
                          ),

                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _openSeries(AudioSeries series) {
    context.push('/audio/series/${series.id}', extra: series);
  }
}