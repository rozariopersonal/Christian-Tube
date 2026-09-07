import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/engines/base_feed_engine.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_reference.dart';
import 'package:mobile/features/bible/services/bible_passage_navigator.dart';
import 'package:mobile/features/engines/scripture/services/bible_download_manager.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:mobile/features/engines/scripture/widgets/bible_version_picker_modal.dart';
import 'package:mobile/features/micro_feed/widgets/card_action_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/wftw_card.dart';
import 'models/wftw_filter_state.dart';
import 'services/wftw_database_service.dart';
import 'widgets/wftw_card_view.dart';
import 'widgets/wftw_filter_sheet.dart';
import 'widgets/wftw_style_sheet.dart';

class WftwFeedEngine implements BaseFeedEngine<WftwCard, WftwFilterState> {
  static final WftwFeedEngine _instance = WftwFeedEngine._internal();
  factory WftwFeedEngine() => _instance;
  WftwFeedEngine._internal();

  final WftwDatabaseService _dbService = WftwDatabaseService();
  final LocalBibleService _bibleService = LocalBibleService();

  static WftwFilterState _cachedFilterState = const WftwFilterState();
  static bool _hasLoadedPrefs = false;

  List<int> _availableYears = [];
  List<int> _availableBooks = [];

  @override
  String get engineType => 'wftw';

  @override
  String? mapLoadError(Object error) => null;

  @override
  String get defaultTabTitle => 'Words';

  @override
  IconData get defaultTabIcon => Icons.auto_awesome_outlined;

  @override
  WftwFilterState get initialFilterState => _cachedFilterState;

  @override
  Future<void> initialize() async {
    await _bibleService.initialize();
    await BookNameService().ensureLoaded();
    await BibleDownloadManager().ensureDefaultInstalled();

    if (!_hasLoadedPrefs) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedVersion = prefs.getString('pref_bible_version') ?? 'TAOBVSI';
        final savedScale = prefs.getDouble('pref_wftw_font_scale') ?? 1.0;
        final savedPreset = prefs.getString('pref_wftw_bg_preset') ?? 'mountain_dawn';
        final savedSort = prefs.getString('pref_wftw_sort_by') ?? 'date';

        _cachedFilterState = WftwFilterState(
          activeVersionId: savedVersion,
          fontSizeScale: savedScale,
          backgroundPreset: savedPreset,
          sortBy: savedSort,
        );
        _hasLoadedPrefs = true;
      } catch (_) {}
    }

    // Sync database in background (downloads if not yet downloaded)
    await _dbService.syncDatabase();

    // Cache available filter choices
    _availableYears = await _dbService.getAvailableYears();
    _availableBooks = await _dbService.getAvailableBooks();
  }

  @override
  Future<List<WftwCard>> fetchItems({
    required WftwFilterState filterState,
    int page = 0,
    int limit = 20,
  }) async {
    try {
      final rows = await _dbService.queryVerses(
        offset: page * limit,
        limit: limit,
        year: filterState.yearFilter,
        bookNumber: filterState.bookFilter,
        sortBy: filterState.sortBy,
      );

      final cards = rows.map((r) => WftwCard.fromMap(r)).toList();

      // Pre-resolve verses for cards that have a primary scripture
      for (final card in cards) {
        if (card.hasPrimaryVerse) {
          final text = _bibleService.resolvePassageSync(
            versionId: filterState.activeVersionId,
            bookNumber: card.bookNumber!,
            chapter: card.chapter!,
            startVerse: card.startVerse!,
            endVerse: card.endVerse,
          );
          if (text != null) {
            card.resolvedText = text;
            card.resolvedVersion = filterState.activeVersionId;
          }
        }
      }

      return cards;
    } catch (e) {
      debugPrint('WFTW Engine fetchItems error: $e');
      rethrow;
    }
  }

  @override
  Widget? buildTopControls(
    BuildContext context,
    WftwFilterState filterState,
    ValueChanged<WftwFilterState> onFilterChanged,
    VoidCallback onOpenManager,
  ) {
    final tokens = context.tokens;
    final onScrim = tokens.onScrim;
    final onScrimMuted = tokens.onScrimMuted;

    final hasActiveFilter = filterState.yearFilter != null ||
        filterState.bookFilter != null ||
        filterState.sortBy != 'date';

    return Row(
      children: [
        // 1. Version Picker Pill
        GestureDetector(
          onTap: () {
            showAdaptiveBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (ctx) => BibleVersionPickerModal(
                activeVersionId: filterState.activeVersionId,
                onSelectVersion: (newVersionId) {
                  final newState =
                      filterState.copyWith(activeVersionId: newVersionId);
                  _cachedFilterState = newState;
                  onFilterChanged(newState);
                },
                onOpenManager: onOpenManager,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.scrim.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tokens.surfaceBorder, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filterState.activeVersionId,
                  style: TextStyle(
                    color: onScrim,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: onScrimMuted,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),

        // 2. Filter & Sort Pill
        GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => WftwFilterSheet(
                currentState: filterState,
                availableYears: _availableYears,
                availableBooks: _availableBooks,
                onApply: (newState) {
                  _cachedFilterState = newState;
                  onFilterChanged(newState);
                },
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.scrim.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasActiveFilter ? tokens.accent : tokens.surfaceBorder,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: hasActiveFilter ? tokens.accent : onScrimMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  filterState.yearFilter != null
                      ? '${filterState.yearFilter}'
                      : (filterState.sortBy == 'book' ? 'By Book' : 'Filter'),
                  style: TextStyle(
                    color: hasActiveFilter ? tokens.accent : onScrim,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildCard(
    BuildContext context,
    WftwCard item,
    WftwFilterState filterState,
    bool isActive,
    GlobalKey repaintBoundaryKey, {
    ValueChanged<int>? onEdgePageShift,
  }) {
    return WftwCardView(
      key: ValueKey(
        '${item.articleId}_${filterState.activeVersionId}_${filterState.fontSizeScale}_${filterState.backgroundPreset}_${item.activeBackground}',
      ),
      card: item,
      filterState: filterState,
      isActive: isActive,
      onEdgePageShift: onEdgePageShift,
      onReferenceTap: item.hasPrimaryVerse
          ? () {
              BiblePassageNavigator.instance.navigateTo(
                BibleReference(
                  bookNumber: item.bookNumber!,
                  chapter: item.chapter!,
                  verse: item.startVerse!,
                  versionId: item.resolvedVersion ?? filterState.activeVersionId,
                ),
                context: context,
              );
            }
          : null,
      onReadArticleTap: () =>
          context.push('/article/${item.articleId}', extra: {'title': item.articleTitle}),
    );
  }

  @override
  List<Widget> buildSideActions(
    BuildContext context,
    WftwCard item,
    WftwFilterState filterState,
    GlobalKey repaintBoundaryKey,
    VoidCallback onRefreshCard,
    ValueChanged<WftwFilterState> onFilterChanged,
  ) {
    final tokens = context.tokens;

    return [
      // 1. Share
      CardActionButton(
        icon: Icons.share_rounded,
        label: 'Share',
        onTap: () async {
          final text = item.hasPrimaryVerse
              ? '“${item.resolvedText ?? ""}”\n\n— ${item.referenceLabel}\nFrom: ${item.articleTitle}'
              : '${item.articleTitle}\n\n${item.fallbackExcerpt ?? ""}';
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Article text copied to clipboard!',
                  style: TextStyle(color: tokens.onSurface),
                ),
                backgroundColor: tokens.surface,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),

      // 2. Style Studio
      CardActionButton(
        icon: Icons.palette_outlined,
        label: 'Style',
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => WftwStyleSheet(
              card: item,
              filterState: filterState,
              onFilterChanged: onFilterChanged,
              onRefreshCard: onRefreshCard,
            ),
          );
        },
      ),

      // 3. Copy
      CardActionButton(
        icon: Icons.copy_rounded,
        label: 'Copy',
        onTap: () async {
          final text = item.hasPrimaryVerse
              ? '“${item.resolvedText ?? ""}”\n\n— ${item.referenceLabel}'
              : '${item.articleTitle}\n\n${item.fallbackExcerpt ?? ""}';
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Copied to clipboard!',
                  style: TextStyle(color: tokens.onSurface),
                ),
                backgroundColor: tokens.surface,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    ];
  }

  @override
  Widget? buildBottomBar(BuildContext context, WftwCard item) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "📝 Read Article" button
        ElevatedButton.icon(
          onPressed: () => context.push('/article/${item.articleId}',
              extra: {'title': item.articleTitle}),
          icon: const Icon(Icons.menu_book_rounded, size: 16),
          label: const Text(
            'Read Article',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.surface.withValues(alpha: 0.92),
            foregroundColor: tokens.onSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            elevation: 4,
          ),
        ),
        if (item.hasPrimaryVerse) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              BiblePassageNavigator.instance.navigateTo(
                BibleReference(
                  bookNumber: item.bookNumber!,
                  chapter: item.chapter!,
                  verse: item.startVerse!,
                  versionId: item.resolvedVersion ?? _cachedFilterState.activeVersionId,
                ),
                context: context,
              );
            },
            icon: const Icon(Icons.auto_stories_rounded, size: 16),
            label: const Text(
              'Read in Bible',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: tokens.scrim.withValues(alpha: 0.5),
              foregroundColor: tokens.onScrim,
              side: BorderSide(color: tokens.surfaceBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Future<void> shareCard(
    BuildContext context,
    WftwCard item,
    GlobalKey repaintBoundaryKey,
  ) async {
    // Basic text copy fallback
    final text = '${item.articleTitle}\n${item.referenceLabel}';
    await Clipboard.setData(ClipboardData(text: text));
  }
}
