import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile/core/engines/base_feed_engine.dart';
import 'package:mobile/features/bible/models/bible_reference.dart';
import 'package:mobile/features/bible/services/bible_passage_navigator.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/scripture_card.dart';
import 'models/scripture_filter_state.dart';
import 'models/scripture_theme_state.dart';
import 'services/bible_download_manager.dart';
import 'services/online_bible_service.dart';
import 'services/saved_scripture_service.dart';
import 'services/scripture_image_exporter.dart';
import 'services/scripture_service.dart';
import '../../../shared/ui/bible_version_pill.dart';
import 'widgets/scripture_card_view.dart';
import 'widgets/verse_action_appearance_sheet.dart';
import 'widgets/scripture_filter_settings_sheet.dart';
import '../../shorts/widgets/shorts_chrome.dart';

class ScriptureEngine
    implements BaseFeedEngine<ScriptureCard, ScriptureFilterState> {
  static final ScriptureEngine _instance = ScriptureEngine._internal();
  factory ScriptureEngine() => _instance;
  ScriptureEngine._internal();

  final ScriptureService _service = ScriptureService();
  static ScriptureFilterState _cachedFilterState =
      const ScriptureFilterState(activeVersionId: 'NASB');
  static bool _hasLoadedPrefs = false;

  @override
  String get engineType => 'scripture';

  @override
  String? mapLoadError(Object error) => null;

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
      final savedVersion = prefs.getString('pref_bible_version');

      // Check downloaded bibles that contain verse text
      final installedIds = await _service.getInstalledVersionIds();

      String activeVersion = 'NASB';
      if (savedVersion != null &&
          (installedIds.contains(savedVersion) ||
              OnlineBibleService.isOnlineVersion(savedVersion))) {
        activeVersion = savedVersion;
      } else if (installedIds.isNotEmpty) {
        activeVersion = installedIds.first;
      } else {
        activeVersion = 'NASB';
      }

      _cachedFilterState = await loadFilterStateForVersion(activeVersion);
      _hasLoadedPrefs = true;
    } catch (_) {}
  }

  void resetRandomDeck() {
    _service.resetRandomDeck();
  }

  Future<ScriptureFilterState> loadFilterStateForVersion(
    String versionId, {
    ScriptureFilterState? baseState,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final meta = BibleDownloadManager.getMeta(versionId);
      final lang = meta.languageCode;

      final defaultFont =
          ScriptureThemeCatalog.getDefaultFontForLanguage(lang);

      final savedScale = prefs.getDouble('pref_bible_${lang}_font_scale') ??
          prefs.getDouble('pref_bible_font_scale') ??
          (baseState?.fontSizeScale ?? _cachedFilterState.fontSizeScale);
      final savedFont = prefs.getString('pref_bible_${lang}_font_family') ??
          (lang == 'en'
              ? prefs.getString('pref_bible_font_family')
              : null) ??
          defaultFont;
      final savedColor = prefs.getString('pref_bible_${lang}_text_color') ??
          prefs.getString('pref_bible_text_color') ??
          (baseState?.textColorHex ?? _cachedFilterState.textColorHex);
      final savedBold = prefs.getBool('pref_bible_${lang}_is_bold') ??
          prefs.getBool('pref_bible_is_bold') ??
          (baseState?.isBold ?? _cachedFilterState.isBold);
      final savedItalic = prefs.getBool('pref_bible_${lang}_is_italic') ??
          prefs.getBool('pref_bible_is_italic') ??
          (baseState?.isItalic ?? _cachedFilterState.isItalic);
      final savedAlign = prefs.getString('pref_bible_${lang}_text_align') ??
          prefs.getString('pref_bible_text_align') ??
          (baseState?.textAlign ?? _cachedFilterState.textAlign);
      final savedBg = prefs.getString('pref_bible_${lang}_bg_preset') ??
          prefs.getString('pref_bible_bg_preset') ??
          (baseState?.backgroundPreset ?? _cachedFilterState.backgroundPreset);
      final savedComparison = prefs.getString('pref_bible_comparison_version') ??
          baseState?.comparisonVersionId;

      return (baseState ?? _cachedFilterState).copyWith(
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
      return (baseState ?? _cachedFilterState).copyWith(activeVersionId: versionId);
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
      categories: filterState.selectedCategories,
      tags: filterState.selectedTags,
      order: filterState.readingOrder,
    );
    final savedService = SavedScriptureService();
    for (final c in cards) {
      c.isSaved = savedService.isSaved(c.id);
    }
    final comparisonId = filterState.comparisonVersionId;
    if (comparisonId != null && comparisonId != filterState.activeVersionId) {
      final eagerCount = cards.length > 3 ? 3 : cards.length;
      await Future.wait(
        cards.take(eagerCount).map((c) => _service.resolveCardComparisonText(c, comparisonId)),
      );
      for (final c in cards.skip(eagerCount)) {
        unawaited(_service.resolveCardComparisonText(c, comparisonId));
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
    final tokens = context.tokens;
    final isDark = context.isDark;
    final activeCount = filterState.activeFilterCount;
    final hasActiveFilter = activeCount > 0;

    final pillBg = isDark
        ? tokens.scrim.withValues(alpha: 0.50)
        : tokens.surface.withValues(alpha: 0.85);

    final fontScalePct = (filterState.fontSizeScale * 100).round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. Version Picker Pill (Theme-aware, Frosted, and Accent-themed)
        BibleVersionPill(
          activeVersionId: filterState.activeVersionId,
          isFrosted: true,
          onOpenManager: onOpenManager,
          onSelectVersion: (newVersionId) async {
            final newState = await loadFilterStateForVersion(
              newVersionId,
              baseState: filterState,
            );
            await _savePreferences(newState);
            onFilterChanged(newState);
          },
        ),

        // 2. Right Controls Cluster: Font Size Stepper Pill + Settings & Filter Button
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick Font Size Stepper Pill [ A- | 100% | A+ ]
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: tokens.surfaceBorder,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.shortsChromeShadow
                            .withValues(alpha: isDark ? 0.3 : 0.08),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A-
                      InkWell(
                        onTap: filterState.fontSizeScale > 0.8
                            ? () {
                                final newScale = (filterState.fontSizeScale - 0.1)
                                    .clamp(0.8, 1.5);
                                final newState = filterState.copyWith(
                                    fontSizeScale: double.parse(
                                        newScale.toStringAsFixed(1)));
                                _savePreferences(newState);
                                onFilterChanged(newState);
                              }
                            : null,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          child: Text(
                            'A-',
                            style: TextStyle(
                              color: filterState.fontSizeScale > 0.8
                                  ? context.shortsChromeFg
                                  : context.shortsChromeFgMuted,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: tokens.surfaceBorder,
                      ),
                      // Percentage (tapping resets to 100%)
                      InkWell(
                        onTap: () {
                          if (filterState.fontSizeScale != 1.0) {
                            final newState =
                                filterState.copyWith(fontSizeScale: 1.0);
                            _savePreferences(newState);
                            onFilterChanged(newState);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                          child: Text(
                            '$fontScalePct%',
                            style: TextStyle(
                              color: filterState.fontSizeScale != 1.0
                                  ? tokens.accent
                                  : context.shortsChromeFgMuted,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: tokens.surfaceBorder,
                      ),
                      // A+
                      InkWell(
                        onTap: filterState.fontSizeScale < 1.5
                            ? () {
                                final newScale = (filterState.fontSizeScale + 0.1)
                                    .clamp(0.8, 1.5);
                                final newState = filterState.copyWith(
                                    fontSizeScale: double.parse(
                                        newScale.toStringAsFixed(1)));
                                _savePreferences(newState);
                                onFilterChanged(newState);
                              }
                            : null,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          child: Text(
                            'A+',
                            style: TextStyle(
                              color: filterState.fontSizeScale < 1.5
                                  ? context.shortsChromeFg
                                  : context.shortsChromeFgMuted,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Settings & Filter Button with Badge
            GestureDetector(
              onTap: () {
                showAdaptiveBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (ctx) => ScriptureFilterSettingsSheet(
                    filterState: filterState,
                    onApply: (newState) async {
                      await _savePreferences(newState);
                      onFilterChanged(newState);
                    },
                  ),
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: hasActiveFilter
                              ? tokens.accent.withValues(
                                  alpha: isDark ? 0.25 : 0.18)
                              : pillBg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: hasActiveFilter
                                ? tokens.accent.withValues(alpha: 0.6)
                                : tokens.surfaceBorder,
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: hasActiveFilter
                                  ? tokens.accent.withValues(alpha: 0.25)
                                  : context.shortsChromeShadow
                                      .withValues(alpha: isDark ? 0.3 : 0.08),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: hasActiveFilter
                                ? tokens.accent
                                : context.shortsChromeFg,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hasActiveFilter)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            '$activeCount',
                            style: TextStyle(
                              color: tokens.background,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
    ValueChanged<ScriptureFilterState>? onFilterChanged,
    VoidCallback? onRefreshCard,
  }) {
    return ScriptureCardView(
      key: ValueKey(
          '${item.id}_${filterState.activeVersionId}_${filterState.textColorHex}_${filterState.activeFontFamily}_${filterState.fontSizeScale}_${filterState.isBold}_${filterState.isItalic}_${filterState.textAlign}_${item.activeBackground}'),
      card: item,
      filterState: filterState,
      isActive: isActive,
      onEdgePageShift: onEdgePageShift,
      onCardTap: () {
        showAdaptiveBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: context.tokens.scrim.withValues(alpha: 0.25),
          isScrollControlled: true,
          builder: (ctx) => VerseActionAppearanceSheet(
            card: item,
            filterState: filterState,
            repaintBoundaryKey: repaintBoundaryKey,
            onFilterChanged: (newState) {
              _savePreferences(newState);
              if (onFilterChanged != null) {
                onFilterChanged(newState);
              }
            },
            onRefreshCard: () {
              if (onRefreshCard != null) {
                onRefreshCard();
              }
            },
          ),
        );
      },
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

    BiblePassageNavigator.instance.navigateTo(
      BibleReference(
        bookNumber: bookNumber,
        chapter: chapter,
        verse: verse,
        versionId: versionId,
      ),
      context: context,
    );
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
    return const [];
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
