import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_dropdown.dart';
import '../controllers/audio_library_controller.dart';
import '../models/audio_series.dart';
import '../widgets/audio_category_chips.dart';
import '../widgets/audio_category_rail.dart';
import '../widgets/audio_continue_listening_card.dart';
import '../widgets/audio_grouped_sections.dart';
import '../widgets/audio_search_bar.dart';
import '../widgets/audio_series_carousel.dart';
import '../widgets/audio_series_grid.dart';
import '../widgets/audio_view_mode_segmented_bar.dart';

/// Main Audio tab screen — browse sermon series with real-time inline search,
/// segmented view modes (Featured, By Category, By Speaker, A–Z), horizontal
/// category rails, and language filtering. Thin assembler: all behavior
/// lives in [AudioLibraryController], the widgets are presentational.
class AudioLibraryScreen extends StatefulWidget {
  final LibraryLanguagesController? langController;

  const AudioLibraryScreen({super.key, this.langController});

  @override
  State<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends State<AudioLibraryScreen> {
  late final AudioLibraryController _controller;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AudioLibraryController(
      langController: widget.langController,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openSeries(AudioSeries series) {
    context.push('/audio/series/${series.id}', extra: series);
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
                icon: const Icon(Icons.refresh),
                color: tokens.onSurfaceMuted,
                tooltip: 'Refresh Library',
                onPressed: () => _controller.loadData(forceRefresh: true),
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _controller.loadData(forceRefresh: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: MaxWidthBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Search Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: AudioSearchBar(
                              controller: _searchController,
                              onChanged: _controller.setSearchQuery,
                              onClear: () {
                                _controller.clearSearch();
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 2. Language Selector
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                          const SizedBox(height: 12),

                          // 3. Format and View Mode Selectors (Hidden while searching to focus on search results)
                          if (!state.isSearching) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SegmentedButton<AudioFormat>(
                                      segments: const [
                                        ButtonSegment(value: AudioFormat.sermons, label: Text('Sermons')),
                                        ButtonSegment(value: AudioFormat.songs, label: Text('Songs')),
                                      ],
                                      selected: {state.selectedFormat},
                                      onSelectionChanged: (set) => _controller.selectFormat(set.first),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: AudioViewModeSegmentedBar(
                                currentMode: state.viewMode,
                                onModeChanged: _controller.setViewMode,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // 4. Dynamic Body Content
                          _buildContent(context, theme, tokens, state),

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

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    AppTokens tokens,
    AudioLibraryViewState state,
  ) {
    // A. SEARCH RESULTS MODE
    if (state.isSearching) {
      final results = state.searchResults;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Search Results (${results.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    _controller.clearSearch();
                  },
                  child: const Text('Clear Search'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (results.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      color: tokens.onSurfaceMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No audio series found for "${state.searchQuery}"',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            AudioSeriesGrid(
              state: state.copyWith(seriesList: results),
              onReset: () {
                _searchController.clear();
                _controller.clearSearch();
              },
              onOpenSeries: _openSeries,
            ),
        ],
      );
    }

    // B. BY CATEGORY (ACCORDION / GROUPED SECTIONS)
    if (state.viewMode == AudioViewMode.byCategory) {
      return AudioGroupedSections(
        groups: state.seriesByCategory,
        onOpenSeries: _openSeries,
        emptyMessage: 'No audio categories found for selected language.',
      );
    }

    // C. BY SPEAKER (ACCORDION / GROUPED SECTIONS)
    if (state.viewMode == AudioViewMode.bySpeaker) {
      return AudioGroupedSections(
        groups: state.seriesBySpeaker,
        onOpenSeries: _openSeries,
        emptyMessage: 'No speakers found for selected language.',
      );
    }

    // D. ALPHABETICAL (A–Z)
    if (state.viewMode == AudioViewMode.alphabetical) {
      return AudioGroupedSections(
        groups: state.seriesAlphabetical,
        onOpenSeries: _openSeries,
        emptyMessage: 'No audio series found for selected language.',
      );
    }

    // E. FEATURED (DEFAULT)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Filter Chips
        if (state.selectedFormat == AudioFormat.sermons) ...[
          AudioCategoryChips(
            categories: AudioLibraryController.categories,
            selected: state.selectedCategory,
            onSelected: _controller.selectCategory,
          ),
          const SizedBox(height: 16),
        ],

        // When a specific category is filtered, show full category grid
        if (state.selectedCategory != 'All') ...[
          AudioSeriesGrid(
            state: state,
            onReset: _controller.resetFilters,
            onOpenSeries: _openSeries,
          ),
        ] else ...[
          // Continue Listening Card
          if (state.lastPlayedTrack != null) ...[
            AudioContinueListeningCard(
              track: state.lastPlayedTrack!,
              savedSeconds: state.lastPlayedSeconds,
            ),
            const SizedBox(height: 20),
          ],

          // Featured Carousel
          if (state.isAllLanguagesSelected && state.filteredSeries.isNotEmpty) ...[
            AudioSeriesCarousel(
              seriesList: state.filteredSeries,
              onTapSeries: _openSeries,
            ),
            const SizedBox(height: 20),
          ],

          // Horizontal Rails per Category (Eliminates massive vertical scroll)
          if (state.selectedFormat == AudioFormat.sermons)
            ..._buildCategoryRails(state)
          else
            AudioSeriesGrid(
              state: state,
              onReset: _controller.resetFilters,
              onOpenSeries: _openSeries,
            ),
        ],
      ],
    );
  }

  List<Widget> _buildCategoryRails(AudioLibraryViewState state) {
    final categorized = state.seriesByCategory;
    final rails = <Widget>[];

    // Priority ordering for category rails
    final railOrder = [
      'Verse By Verse',
      'Foundations',
      'Discipleship',
      'Christian Living',
      'Daily Devotions',
      'Family & Home',
      'The Church',
      'Conferences',
      'General Sermons',
    ];

    for (final cat in railOrder) {
      final list = categorized[cat];
      if (list != null && list.isNotEmpty) {
        rails.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: AudioCategoryRail(
              title: cat,
              seriesList: list,
              onSeeAll: () => _controller.selectCategory(cat),
              onTapSeries: _openSeries,
            ),
          ),
        );
      }
    }

    // Add any remaining categories not in priority list
    for (final entry in categorized.entries) {
      if (!railOrder.contains(entry.key) && entry.value.isNotEmpty) {
        rails.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: AudioCategoryRail(
              title: entry.key,
              seriesList: entry.value,
              onSeeAll: () => _controller.selectCategory(entry.key),
              onTapSeries: _openSeries,
            ),
          ),
        );
      }
    }

    if (rails.isEmpty && state.filteredSeries.isNotEmpty) {
      rails.add(
        AudioSeriesGrid(
          state: state,
          onReset: _controller.resetFilters,
          onOpenSeries: _openSeries,
        ),
      );
    }

    return rails;
  }
}