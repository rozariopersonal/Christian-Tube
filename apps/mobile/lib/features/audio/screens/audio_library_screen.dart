import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/theme/app_tokens.dart';
import '../../books/models/book_language_meta.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';
import '../services/audio_storage_service.dart';
import '../widgets/audio_language_dropdown.dart';
import '../widgets/audio_search_delegate.dart';

/// Main Audio tab screen — browse sermon series, continue listening, explore topics,
/// and filter by category and language.
class AudioLibraryScreen extends StatefulWidget {
  const AudioLibraryScreen({super.key});

  @override
  State<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends State<AudioLibraryScreen> {
  final AudioCatalogService _catalogService = AudioCatalogService();
  final AudioStorageService _storageService = AudioStorageService();

  List<AudioSeries> _seriesList = [];
  AudioTrack? _lastPlayedTrack;
  int _lastPlayedSeconds = 0;
  bool _isLoading = true;

  String _selectedCategory = 'All';
  Set<String> _selectedLanguages = {'All'};
  List<String> _availableLanguages = ['All'];
  Map<String, int> _languageTrackCounts = {};

  static const String _prefKeyLanguages = 'audio_library_languages';

  static const _categories = [
    'All',
    'Bible Survey',
    'Foundations',
    'Discipleship',
    'Christian Living',
    'Daily Devotions',
    'Verse By Verse',
    'Family & Home',
    'The Church',
    'Conferences',
    'General Sermons',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool get _isAllLanguagesSelected =>
      _selectedLanguages.isEmpty ||
      _selectedLanguages.any((l) => l.toLowerCase() == 'all');

  Future<void> _loadData({bool forceRefresh = false}) async {
    final catalog = await _catalogService.getCatalog(forceRefresh: forceRefresh);
    final lastTrack = await _storageService.getLastTrack();
    int lastSec = 0;
    if (lastTrack != null) {
      lastSec = await _storageService.getPosition(lastTrack.id);
    }

    final counts = <String, int>{'All': 0};
    final Set<String> uniqueLangs = {};

    for (final s in catalog) {
      final lang = s.language.trim();
      if (lang.isEmpty) continue;
      uniqueLangs.add(lang);
      counts['All'] = (counts['All'] ?? 0) + s.trackCount;
      counts[lang] = (counts[lang] ?? 0) + s.trackCount;
    }

    final sortedLangs = uniqueLangs.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefKeyLanguages);
    final initialSelection = (saved != null && saved.isNotEmpty)
        ? saved.toSet()
        : _selectedLanguages;

    if (mounted) {
      setState(() {
        _seriesList = catalog;
        _lastPlayedTrack = lastTrack;
        _lastPlayedSeconds = lastSec;
        _languageTrackCounts = counts;
        _availableLanguages = ['All', ...sortedLangs];
        _selectedLanguages = initialSelection;
        _isLoading = false;
      });
    }
  }

  void _onLanguagesSelected(Set<String> newSelection) {
    final valid = newSelection.isEmpty ? {'All'} : newSelection;
    setState(() {
      _selectedLanguages = valid;
    });
    SharedPreferences.getInstance().then((p) {
      p.setStringList(_prefKeyLanguages, valid.toList());
    });
  }

  List<AudioSeries> get _filteredSeries {
    final isAll = _isAllLanguagesSelected;

    return _seriesList.where((s) {
      final matchesCategory =
          _selectedCategory == 'All' || s.category == _selectedCategory;
      if (!matchesCategory) return false;

      if (isAll) return true;

      final sLangLower = s.language.toLowerCase();
      final sMeta = BookLanguageMeta.fromCode(s.language);

      return _selectedLanguages.any((l) {
        final lLower = l.toLowerCase();
        final lMeta = BookLanguageMeta.fromCode(l);
        return lLower == sLangLower ||
            lMeta.englishName.toLowerCase() == sLangLower ||
            lLower == sMeta.code.toLowerCase() ||
            lMeta.code.toLowerCase() == sMeta.code.toLowerCase();
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final isAllLang = _isAllLanguagesSelected;

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
                delegate: AudioSearchDelegate(_seriesList),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadData(forceRefresh: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language Selection Dropdown (Books Library style)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AudioLanguageDropdown(
                        selectedLanguages: _selectedLanguages,
                        availableLanguages: _availableLanguages,
                        trackCounts: _languageTrackCounts,
                        onLanguagesSelected: _onLanguagesSelected,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Categories Bar
                    _buildCategoryChips(tokens, theme),
                    const SizedBox(height: 16),

                    // Featured Series Carousel (when on All)
                    if (_selectedCategory == 'All' && isAllLang) ...[
                      _buildSeriesCarousel(context, tokens, theme),
                      const SizedBox(height: 24),
                    ],

                    // Continue Listening Card
                    if (_lastPlayedTrack != null) ...[
                      _buildContinueListening(context, tokens, theme),
                      const SizedBox(height: 24),
                    ],

                    // Topics Grid (only when on All)
                    if (_selectedCategory == 'All' && isAllLang) ...[
                      _buildTopicsSection(context, tokens, theme),
                      const SizedBox(height: 24),
                    ],

                    // All Series Grid for selected category/filter
                    _buildSeriesGrid(context, tokens, theme),

                    // Space for persistent MiniPlayer
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryChips(AppTokens tokens, ThemeData theme) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return FilterChip(
            label: Text(cat),
            selected: isSelected,
            labelStyle: theme.textTheme.bodySmall?.copyWith(
              color: isSelected ? theme.colorScheme.onPrimary : tokens.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            selectedColor: theme.colorScheme.primary,
            backgroundColor: tokens.surfaceElevated,
            checkmarkColor: theme.colorScheme.onPrimary,
            side: BorderSide(
              color: isSelected ? theme.colorScheme.primary : tokens.surfaceBorder,
              width: 0.8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (_) {
              setState(() => _selectedCategory = cat);
            },
          );
        },
      ),
    );
  }

  Widget _buildSeriesCarousel(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    final featured = _seriesList.take(8).toList();
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
              return _buildSeriesCard(context, series, tokens, theme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesCard(
    BuildContext context,
    AudioSeries series,
    AppTokens tokens,
    ThemeData theme,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        context.push(
          '/audio/series/${series.id}',
          extra: series,
        );
      },
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 150,
                height: 150,
                color: tokens.surfaceVariant,
                child: series.coverUrl != null && series.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: series.coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildCardFallback(theme),
                      )
                    : _buildCardFallback(theme),
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
      ),
    );
  }

  Widget _buildCardFallback(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.headphones,
        size: 40,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildContinueListening(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    final track = _lastPlayedTrack!;
    final progress = track.durationSeconds > 0
        ? (_lastPlayedSeconds / track.durationSeconds).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.surfaceBorder, width: 0.8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 54,
                height: 54,
                color: tokens.surfaceVariant,
                child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.headphones,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.headphones,
                        color: theme.colorScheme.primary,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continue Listening',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: tokens.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: () {
                AudioPlayerController.instance.playTrack(
                  track,
                  resumePositionSec: _lastPlayedSeconds,
                );
              },
              child: Text(percent > 0 ? '$percent%' : 'Resume'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicsSection(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    final topics = [
      {'title': 'Overcoming Sin', 'category': 'Christian Living', 'icon': Icons.shield_outlined},
      {'title': 'Holy Spirit', 'category': 'Christian Living', 'icon': Icons.local_fire_department_outlined},
      {'title': 'Family & Home', 'category': 'Family & Home', 'icon': Icons.home_outlined},
      {'title': 'Faith & Victory', 'category': 'Foundations', 'icon': Icons.emoji_events_outlined},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore Topics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topics.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
            ),
            itemBuilder: (context, index) {
              final topic = topics[index];
              return Material(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() {
                      _selectedCategory = topic['category'] as String;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          topic['icon'] as IconData,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            topic['title'] as String,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: tokens.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesGrid(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    final filtered = _filteredSeries;
    final isAllLang = _isAllLanguagesSelected;
    final String langSuffix;
    if (isAllLang) {
      langSuffix = '';
    } else if (_selectedLanguages.length == 1) {
      final meta = BookLanguageMeta.fromCode(_selectedLanguages.first);
      langSuffix = ' • ${meta.englishName}';
    } else {
      langSuffix = ' • ${_selectedLanguages.length} Languages';
    }

    final headerTitle = _selectedCategory == 'All'
        ? 'All Series (${filtered.length}$langSuffix)'
        : '$_selectedCategory (${filtered.length}$langSuffix)';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                headerTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tokens.onSurface,
                ),
              ),
              if (_selectedCategory != 'All' || !isAllLang)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedCategory = 'All';
                      _selectedLanguages = {'All'};
                    });
                    SharedPreferences.getInstance().then((p) {
                      p.setStringList(_prefKeyLanguages, ['All']);
                    });
                  },
                  child: const Text('Reset'),
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
                final screenClass = ScreenClass.of(context);
                final crossAxisCount = screenClass.isCompact
                    ? 2
                    : (screenClass == ScreenClass.medium ? 3 : 4);

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) {
                    final series = filtered[index];
                    return _buildSeriesCard(context, series, tokens, theme);
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}
