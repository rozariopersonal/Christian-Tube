import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/engines/base_feed_engine.dart';
import 'package:mobile/features/micro_feed/widgets/card_action_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/scripture_card.dart';
import 'models/scripture_filter_state.dart';
import 'models/scripture_theme_state.dart';
import 'services/bible_download_manager.dart';
import 'services/saved_scripture_service.dart';
import 'services/scripture_image_exporter.dart';
import 'services/scripture_service.dart';
import 'screens/saved_scriptures_screen.dart';
import 'widgets/bible_version_picker_modal.dart';
import 'widgets/scripture_card_view.dart';
import 'widgets/style_studio_sheet.dart';

class ScriptureEngine
    implements BaseFeedEngine<ScriptureCard, ScriptureFilterState> {
  static final ScriptureEngine _instance = ScriptureEngine._internal();
  factory ScriptureEngine() => _instance;
  ScriptureEngine._internal();

  final ScriptureService _service = ScriptureService();
  static ScriptureFilterState _cachedFilterState =
      const ScriptureFilterState(activeVersionId: 'WEB');
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

      return ScriptureFilterState(
        activeVersionId: versionId,
        fontSizeScale: savedScale,
        activeFontFamily: savedFont,
        textColorHex: savedColor,
        isBold: savedBold,
        isItalic: savedItalic,
        textAlign: savedAlign,
        backgroundPreset: savedBg,
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
    );
    final savedService = SavedScriptureService();
    for (final c in cards) {
      c.isSaved = savedService.isSaved(c.id);
    }
    return cards;
  }

  Future<void> resolveCard(ScriptureCard card, String versionId) async {
    await _service.resolveCardText(card, versionId);
    card.isSaved = SavedScriptureService().isSaved(card.id);
  }

  @override
  Widget? buildTopControls(
    BuildContext context,
    ScriptureFilterState filterState,
    ValueChanged<ScriptureFilterState> onFilterChanged,
    VoidCallback onOpenManager,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. Version Picker Pill
        GestureDetector(
          onTap: () {
            showModalBottomSheet(
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
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 15,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 6),
                Text(
                  filterState.activeVersionId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),

        // 2. Font Size Quick Adjuster Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Text(
                  'A⁻',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                onPressed: () {
                  final newScale = (filterState.fontSizeScale - 0.08)
                      .clamp(0.80, 1.35);
                  final newState =
                      filterState.copyWith(fontSizeScale: newScale);
                  _savePreferences(newState);
                  onFilterChanged(newState);
                },
              ),
              Container(
                width: 1,
                height: 14,
                color: Colors.white24,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Text(
                  'A⁺',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onPressed: () {
                  final newScale = (filterState.fontSizeScale + 0.08)
                      .clamp(0.80, 1.35);
                  final newState =
                      filterState.copyWith(fontSizeScale: newScale);
                  _savePreferences(newState);
                  onFilterChanged(newState);
                },
              ),
            ],
          ),
        ),

        // 3. Saved Verses / Bookmarks Quick Access
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
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: count > 0
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                        : Colors.white12,
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
                          ? const Color(0xFFF59E0B)
                          : Colors.white70,
                      size: 16,
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
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
    GlobalKey repaintBoundaryKey,
  ) {
    return ScriptureCardView(
      key: ValueKey(
          '${item.id}_${filterState.activeVersionId}_${filterState.textColorHex}_${filterState.activeFontFamily}_${filterState.fontSizeScale}_${filterState.isBold}_${filterState.isItalic}_${filterState.textAlign}_${item.activeBackground}'),
      card: item,
      filterState: filterState,
      isActive: isActive,
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
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black.withValues(alpha: 0.25),
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

      // 3. Copy Scripture Text
      CardActionButton(
        icon: Icons.copy_rounded,
        label: 'Copy',
        onTap: () async {
          final text =
              '“${item.resolvedText ?? ""}”\n\n— ${item.referenceLabel} (${item.resolvedVersion ?? filterState.activeVersionId})';
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Scripture copied to clipboard!'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),

      // 4. Bookmark / Favorite
      CardActionButton(
        icon: item.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        iconColor: item.isSaved ? const Color(0xFFF59E0B) : Colors.white,
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
                content: Text(isNowSaved
                    ? 'Saved ${item.referenceLabel} to favorites!'
                    : 'Removed from favorites'),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                action: isNowSaved
                    ? SnackBarAction(
                        label: 'View Saved',
                        textColor: const Color(0xFFF59E0B),
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
