import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/engines/base_feed_engine.dart';
import 'package:mobile/features/micro_feed/widgets/card_action_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/scripture_card.dart';
import 'models/scripture_filter_state.dart';
import 'models/scripture_theme_state.dart';
import 'services/scripture_image_exporter.dart';
import 'services/scripture_service.dart';
import 'widgets/bible_version_picker_modal.dart';
import 'widgets/scripture_card_view.dart';
import 'widgets/style_studio_sheet.dart';

class ScriptureEngine
    implements BaseFeedEngine<ScriptureCard, ScriptureFilterState> {
  final ScriptureService _service = ScriptureService();
  ScriptureFilterState _cachedFilterState =
      const ScriptureFilterState(activeVersionId: 'WEB');

  @override
  String get engineType => 'scripture';

  @override
  String get defaultTabTitle => 'Words';

  @override
  IconData get defaultTabIcon => Icons.auto_awesome_outlined;

  @override
  Future<void> initialize() async {
    await _service.initialize();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getString('pref_bible_version') ?? 'WEB';
      final savedScale = prefs.getDouble('pref_bible_font_scale') ?? 1.0;
      final savedFont = prefs.getString('pref_bible_font_family') ?? 'Playfair';
      final savedColor = prefs.getString('pref_bible_text_color') ?? '#FFFFFF';
      final savedBold = prefs.getBool('pref_bible_is_bold') ?? false;
      final savedItalic = prefs.getBool('pref_bible_is_italic') ?? false;
      final savedAlign = prefs.getString('pref_bible_text_align') ?? 'center';

      _cachedFilterState = ScriptureFilterState(
        activeVersionId: savedVersion,
        fontSizeScale: savedScale,
        activeFontFamily: savedFont,
        textColorHex: savedColor,
        isBold: savedBold,
        isItalic: savedItalic,
        textAlign: savedAlign,
      );
    } catch (_) {}
  }

  Future<void> _savePreferences(ScriptureFilterState state) async {
    _cachedFilterState = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pref_bible_version', state.activeVersionId);
      await prefs.setDouble('pref_bible_font_scale', state.fontSizeScale);
      await prefs.setString('pref_bible_font_family', state.activeFontFamily);
      await prefs.setString('pref_bible_text_color', state.textColorHex);
      await prefs.setBool('pref_bible_is_bold', state.isBold);
      await prefs.setBool('pref_bible_is_italic', state.isItalic);
      await prefs.setString('pref_bible_text_align', state.textAlign);
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
    return _service.fetchCards(
      activeVersionId: filterState.activeVersionId,
      page: page,
      limit: limit,
    );
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
                onSelectVersion: (newVersionId) {
                  final newState =
                      filterState.copyWith(activeVersionId: newVersionId);
                  _savePreferences(newState);
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
  ) {
    return [
      // 1. Share Image Button
      CardActionButton(
        icon: Icons.share_rounded,
        label: 'Share',
        onTap: () => ScriptureImageExporter.captureAndShare(
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
            isScrollControlled: true,
            builder: (ctx) => StyleStudioSheet(
              card: item,
              filterState: filterState,
              onFilterChanged: (newState) {
                _savePreferences(newState);
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
        onTap: () {
          item.isSaved = !item.isSaved;
          onRefreshCard();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(item.isSaved ? 'Saved to your favorites!' : 'Removed from favorites'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
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
