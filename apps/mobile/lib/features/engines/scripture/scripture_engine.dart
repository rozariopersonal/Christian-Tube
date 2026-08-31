import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/engines/base_feed_engine.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';
import 'package:mobile/features/micro_feed/widgets/card_action_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/scripture_card.dart';
import 'models/scripture_filter_state.dart';
import 'models/scripture_theme_state.dart';
import 'services/bible_download_manager.dart';
import 'services/book_name_service.dart';
import 'services/saved_scripture_service.dart';
import 'services/scripture_image_exporter.dart';
import 'services/scripture_service.dart';
import 'screens/saved_scriptures_screen.dart';
import 'widgets/bible_version_picker_modal.dart';
import 'widgets/compare_version_picker_sheet.dart';
import 'widgets/scripture_card_view.dart';
import 'widgets/style_studio_sheet.dart';

class ScriptureEngine
    implements BaseFeedEngine<ScriptureCard, ScriptureFilterState> {
  static final ScriptureEngine _instance = ScriptureEngine._internal();
  factory ScriptureEngine() => _instance;
  ScriptureEngine._internal();

  final ScriptureService _service = ScriptureService();
  static ScriptureFilterState _cachedFilterState =
      const ScriptureFilterState(activeVersionId: BibleDownloadManager.defaultVersionId);
  static bool _hasLoadedPrefs = false;

  @override
  String get engineType => 'scripture';

  @override
  String get defaultTabTitle => 'Words';

  @override
  IconData get defaultTabIcon => Icons.auto_awesome_outlined;

  @override
  Future<void> initialize() async {
    await _service.initialize();
    await SavedScriptureService().initialize();
    if (!_hasLoadedPrefs) {
      _service.resetRandomDeck();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion =
          prefs.getString('pref_bible_version') ?? _cachedFilterState.activeVersionId;
      _cachedFilterState = await loadFilterStateForVersion(savedVersion);
      _hasLoadedPrefs = true;
    } catch (_) {}

    // Pull the default bible (TAOBVSI) on first run so the feed and bible page
    // have real verse text; it is served from the releases repo.
    await BibleDownloadManager().ensureDefaultInstalled();
  }

  void resetRandomDeck() {
    _service.resetRandomDeck();
  }

  Future<ScriptureFilterState> loadFilterStateForVersion(String versionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final meta = BibleDownloadManager.getMeta(versionId);
      final lang = meta.languageCode;

      final defaultFont =
          ScriptureThemeCatalog.getDefaultFontForLanguage(lang);

      final savedScale = prefs.getDouble('pref_bible_${lang}_font_scale') ??
          prefs.getDouble('pref_bible_font_scale') ??
          _cachedFilterState.fontSizeScale;
      final savedFont = prefs.getString('pref_bible_${lang}_font_family') ??
          (lang == 'en'
              ? prefs.getString('pref_bible_font_family')
              : null) ??
          defaultFont;
      final savedColor = prefs.getString('pref_bible_${lang}_text_color') ??
          prefs.getString('pref_bible_text_color') ??
          _cachedFilterState.textColorHex;
      final savedBold = prefs.getBool('pref_bible_${lang}_is_bold') ??
          prefs.getBool('pref_bible_is_bold') ??
          _cachedFilterState.isBold;
      final savedItalic = prefs.getBool('pref_bible_${lang}_is_italic') ??
          prefs.getBool('pref_bible_is_italic') ??
          _cachedFilterState.isItalic;
      final savedAlign = prefs.getString('pref_bible_${lang}_text_align') ??
          prefs.getString('pref_bible_text_align') ??
          _cachedFilterState.textAlign;
      final savedBg = prefs.getString('pref_bible_${lang}_bg_preset') ??
          prefs.getString('pref_bible_bg_preset') ??
          _cachedFilterState.backgroundPreset;
      final savedComparison = prefs.getString('pref_bible_comparison_version');

      return ScriptureFilterState(
        activeVersionId: versionId,
        fontSizeScale: savedScale,
        activeFontFamily: savedFont,
        textColorHex: savedColor,
        isBold: savedBold,
        isItalic: savedItalic,
        textAlign: savedAlign,
        backgroundPreset: savedBg,
        comparisonVersionId: savedComparison,
      );
    } catch (_) {
      return ScriptureFilterState(activeVersionId: versionId);
    }
  }

  Future<void> _savePreferences(ScriptureFilterState state) async {
    _cachedFilterState = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      final meta = BibleDownloadManager.getMeta(state.activeVersionId);
      final lang = meta.languageCode;

      // 1. Save Active Version
      await prefs.setString('pref_bible_version', state.activeVersionId);

      // 1b. Save Comparison Version
      if (state.comparisonVersionId != null) {
        await prefs.setString(
            'pref_bible_comparison_version', state.comparisonVersionId!);
      } else {
        await prefs.remove('pref_bible_comparison_version');
      }

      // 2. Save Per-Language Styles
      await prefs.setDouble('pref_bible_${lang}_font_scale', state.fontSizeScale);
      await prefs.setString('pref_bible_${lang}_font_family', state.activeFontFamily);
      await prefs.setString('pref_bible_${lang}_text_color', state.textColorHex);
      await prefs.setBool('pref_bible_${lang}_is_bold', state.isBold);
      await prefs.setBool('pref_bible_${lang}_is_italic', state.isItalic);
      await prefs.setString('pref_bible_${lang}_text_align', state.textAlign);
      await prefs.setString('pref_bible_${lang}_bg_preset', state.backgroundPreset);

      // 3. Fallback Global Persistence
      await prefs.setString('pref_bible_text_color', state.textColorHex);
      await prefs.setString('pref_bible_bg_preset', state.backgroundPreset);
      await prefs.setDouble('pref_bible_font_scale', state.fontSizeScale);
      if (lang == 'en') {
        await prefs.setString('pref_bible_font_family', state.activeFontFamily);
      }
    } catch (_) {}
  }

  @override
  ScriptureFilterState get initialFilterState => _cachedFilterState;

  @override
  Future<List<ScriptureCard>> fetchItems({
    required ScriptureFilterState filterState,
    int page = 0,
    int limit = 20,
  }) async {
    final cards = await _service.fetchCards(
      activeVersionId: filterState.activeVersionId,
      page: page,
      limit: limit,
      bookFilter: filterState.bookFilter,
      testamentFilter: filterState.testamentFilter,
    );
    final savedService = SavedScriptureService();
    for (final c in cards) {
      c.isSaved = savedService.isSaved(c.id);
    }
    final comparisonId = filterState.comparisonVersionId;
    if (comparisonId != null && comparisonId != filterState.activeVersionId) {
      for (final c in cards) {
        await _service.resolveCardComparisonText(c, comparisonId);
      }
    }
    return cards;
  }

  Future<void> resolveCard(
    ScriptureCard card,
    String versionId, {
    String? comparisonVersionId,
  }) async {
    await _service.resolveCardText(card, versionId);
    final comparison = comparisonVersionId ?? _cachedFilterState.comparisonVersionId;
    if (comparison != null && comparison != versionId) {
      await _service.resolveCardComparisonText(card, comparison);
    } else {
      card.comparisonText = null;
      card.comparisonVersion = null;
    }
    card.isSaved = SavedScriptureService().isSaved(card.id);
  }

  /// Resolves (or clears) only the comparison column, leaving the primary
  /// version text untouched. Used when the comparison version changes.
  Future<void> resolveCardComparison(
    ScriptureCard card,
    String? comparisonVersionId,
  ) async {
    if (comparisonVersionId != null &&
        comparisonVersionId != _cachedFilterState.activeVersionId) {
      await _service.resolveCardComparisonText(card, comparisonVersionId);
    } else {
      card.comparisonText = null;
      card.comparisonVersion = null;
    }
  }

  @override
  Widget? buildTopControls(
    BuildContext context,
    ScriptureFilterState filterState,
    ValueChanged<ScriptureFilterState> onFilterChanged,
    VoidCallback onOpenManager,
  ) {
    const testaments = ['All', 'Old Testament', 'New Testament'];
    const otBooks = [
      'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth', 
      '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra', 
      'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 
      'Isaiah', 'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos', 
      'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi'
    ];
    const ntBooks = [
      'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians', '2 Corinthians', 
      'Galatians', 'Ephesians', 'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians', 
      '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James', '1 Peter', '2 Peter', 
      '1 John', '2 John', '3 John', 'Jude', 'Revelation'
    ];
    
    List<String> availableBooks = ['All Books'];
    if (filterState.testamentFilter == 'Old Testament') {
      availableBooks.addAll(otBooks);
    } else if (filterState.testamentFilter == 'New Testament') {
      availableBooks.addAll(ntBooks);
    } else {
      availableBooks.addAll(otBooks);
      availableBooks.addAll(ntBooks);
    }

    final tokens = context.tokens;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
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
                        onSelectVersion: (newVersionId) async {
                          final newState = await loadFilterStateForVersion(newVersionId);
                          await _savePreferences(newState);
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
                      border: Border.all(
                        color: tokens.surfaceBorder,
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.scrim.withValues(alpha: 0.3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 15,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          filterState.activeVersionId,
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: tokens.onSurfaceMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Testament Picker Pill
                PopupMenuButton<String>(
                  color: tokens.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    final newTestament = value == 'All' ? null : value;
                    // Reset book if testament changes
                    final newState = filterState.copyWith(
                      testamentFilter: newTestament,
                      clearTestamentFilter: value == 'All',
                      clearBookFilter: true, // Book needs to be reset if testament changes
                    );
                    _savePreferences(newState);
                    onFilterChanged(newState);
                  },
                  itemBuilder: (context) {
                    return testaments.map((t) {
                      return PopupMenuItem<String>(
                        value: t,
                        child: Text(t, style: TextStyle(color: tokens.onSurface)),
                      );
                    }).toList();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: tokens.scrim.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tokens.surfaceBorder,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          filterState.testamentFilter ?? 'All',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: tokens.onSurfaceMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Book Picker Pill
                PopupMenuButton<String>(
                  color: tokens.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  constraints: const BoxConstraints(maxHeight: 350),
                  onSelected: (value) {
                    final newBook = value == 'All Books' ? null : value;
                    final newState = filterState.copyWith(
                      bookFilter: newBook,
                      clearBookFilter: value == 'All Books',
                    );
                    _savePreferences(newState);
                    onFilterChanged(newState);
                  },
                  itemBuilder: (context) {
                    return availableBooks.map((b) {
                      return PopupMenuItem<String>(
                        value: b,
                        child: Text(b, style: TextStyle(color: tokens.onSurface)),
                      );
                    }).toList();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: tokens.scrim.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tokens.surfaceBorder,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          filterState.bookFilter ?? 'All Books',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: tokens.onSurfaceMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 4. Saved Verses Quick Access
        ValueListenableBuilder<int>(
          valueListenable: SavedScriptureService().savedCountNotifier,
          builder: (context, count, _) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const SavedScripturesScreen(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: tokens.scrim.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: count > 0
                        ? tokens.accent.withValues(alpha: 0.6)
                        : tokens.surfaceBorder,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      count > 0
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: count > 0
                          ? tokens.accent
                          : tokens.onSurfaceMuted,
                      size: 16,
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: TextStyle(
                          color: tokens.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget buildCard(
    BuildContext context,
    ScriptureCard item,
    ScriptureFilterState filterState,
    bool isActive,
    GlobalKey repaintBoundaryKey, {
    ValueChanged<int>? onEdgePageShift,
  }) {
    return ScriptureCardView(
      key: ValueKey(
          '${item.id}_${filterState.activeVersionId}_${filterState.textColorHex}_${filterState.activeFontFamily}_${filterState.fontSizeScale}_${filterState.isBold}_${filterState.isItalic}_${filterState.textAlign}_${item.activeBackground}'),
      card: item,
      filterState: filterState,
      isActive: isActive,
      onEdgePageShift: onEdgePageShift,
      onReferenceTap: () => _openInBibleReader(context, item, filterState),
    );
  }

  /// Launches the Bible reader at the passage shown on the tapped card,
  /// switching the reader to the feed's active version and scrolling to the
  /// verse. Uses the version-specific verse mapping so the reader lands on the
  /// exact passage the reader would display for that translation.
  void _openInBibleReader(
    BuildContext context,
    ScriptureCard card,
    ScriptureFilterState filterState,
  ) {
    final versionId = card.resolvedVersion ?? filterState.activeVersionId;
    int bookNumber = card.bookNumber;
    int chapter = card.chapter;
    int verse = card.startVerse;

    final mapping = card.verseMappings?[versionId];
    if (mapping is Map) {
      bookNumber = mapping['bookNumber'] ?? bookNumber;
      chapter = mapping['chapter'] ?? chapter;
      verse = mapping['startVerse'] ?? verse;
    }

    final bookName = BookNameService.englishNameFor(bookNumber);
    final encoded = Uri.encodeQueryComponent(bookName);
    context.push(
        '/bible?version=$versionId&book=$encoded&chapter=$chapter&verse=$verse');
  }

  @override
  List<Widget> buildSideActions(
    BuildContext context,
    ScriptureCard item,
    ScriptureFilterState filterState,
    GlobalKey repaintBoundaryKey,
    VoidCallback onRefreshCard,
    ValueChanged<ScriptureFilterState> onFilterChanged,
  ) {
    final tokens = context.tokens;

    return [
      // 1. Share Image Button
      CardActionButton(
        icon: Icons.share_rounded,
        label: 'Share',
        onTap: () => ScriptureImageExporter.captureAndShare(
          context: context,
          boundaryKey: repaintBoundaryKey,
          card: item,
          activeVersionId: filterState.activeVersionId,
          fontFamily: filterState.activeFontFamily,
          fontSizeScale: filterState.fontSizeScale,
          textColorHex: filterState.textColorHex,
          isBold: filterState.isBold,
          isItalic: filterState.isItalic,
          textAlign: filterState.textAlign,
        ),
      ),

      // 2. Style & Theme Studio
      CardActionButton(
        icon: Icons.palette_outlined,
        label: 'Style',
        onTap: () {
          showAdaptiveBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            barrierColor: tokens.scrim.withValues(alpha: 0.25),
            isScrollControlled: true,
            builder: (ctx) => StyleStudioSheet(
              card: item,
              filterState: filterState,
              onFilterChanged: (newState) {
                _savePreferences(newState);
                onFilterChanged(newState);
                onRefreshCard();
              },
              onRefreshCard: onRefreshCard,
            ),
          );
        },
      ),

      // 2b. Compare Version
      CardActionButton(
        icon: filterState.comparisonVersionId == null
            ? Icons.compare_arrows_rounded
            : Icons.compare_rounded,
        iconColor: filterState.comparisonVersionId != null
            ? tokens.accent
            : tokens.onSurface,
        label: filterState.comparisonVersionId ?? 'Compare',
        onTap: () {
          showAdaptiveBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            barrierColor: tokens.scrim.withValues(alpha: 0.25),
            isScrollControlled: true,
            builder: (ctx) => CompareVersionPickerSheet(
              activeVersionId: filterState.activeVersionId,
              currentComparisonId: filterState.comparisonVersionId,
              onSelectComparison: (comparisonId) {
                final newState = filterState.copyWith(
                  comparisonVersionId: comparisonId,
                  clearComparisonVersion: comparisonId == null,
                );
                _savePreferences(newState);
                onFilterChanged(newState);
              },
            ),
          );
        },
      ),

      // 3. Copy Scripture Text
      CardActionButton(
        icon: Icons.copy_rounded,
        label: 'Copy',
        onTap: () async {
          final text =
              '“${item.resolvedText ?? ""}”\n\n— ${item.referenceLabel} (${item.resolvedVersion ?? filterState.activeVersionId})';
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            final tokens = context.tokens;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Scripture copied to clipboard!',
                  style: TextStyle(color: tokens.onSurface),
                ),
                backgroundColor: tokens.surfaceElevated,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),

      // 4. Bookmark / Favorite
      CardActionButton(
        icon: item.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        iconColor: item.isSaved ? tokens.accent : tokens.onSurface,
        label: item.isSaved ? 'Saved' : 'Save',
        onTap: () async {
          final isNowSaved = await SavedScriptureService().toggleSave(
            item,
            filterState.activeVersionId,
          );
          item.isSaved = isNowSaved;
          onRefreshCard();
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isNowSaved
                      ? 'Saved ${item.referenceLabel} to favorites!'
                      : 'Removed from favorites',
                  style: TextStyle(color: tokens.onSurface),
                ),
                backgroundColor: tokens.surfaceElevated,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                action: isNowSaved
                    ? SnackBarAction(
                        label: 'View Saved',
                        textColor: tokens.accent,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => const SavedScripturesScreen(),
                            ),
                          );
                        },
                      )
                    : null,
              ),
            );
          }
        },
      ),
    ];
  }

  @override
  Widget? buildBottomBar(BuildContext context, ScriptureCard item) {
    return null; // Phase 1: Clean view without bottom clutter
  }

  @override
  Future<void> shareCard(
    BuildContext context,
    ScriptureCard item,
    GlobalKey repaintBoundaryKey,
  ) async {
    await ScriptureImageExporter.captureAndShare(
      context: context,
      boundaryKey: repaintBoundaryKey,
      card: item,
      activeVersionId: _cachedFilterState.activeVersionId,
      fontFamily: _cachedFilterState.activeFontFamily,
      fontSizeScale: _cachedFilterState.fontSizeScale,
      textColorHex: _cachedFilterState.textColorHex,
      isBold: _cachedFilterState.isBold,
      isItalic: _cachedFilterState.isItalic,
      textAlign: _cachedFilterState.textAlign,
    );
  }
}
