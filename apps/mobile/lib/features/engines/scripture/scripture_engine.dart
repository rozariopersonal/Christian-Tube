import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/engines/base_feed_engine.dart';
import '../../micro_feed/widgets/card_action_button.dart';
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

  @override
  String get engineType => 'scripture';

  @override
  String get defaultTabTitle => 'Words';

  @override
  IconData get defaultTabIcon => Icons.auto_awesome_outlined;

  @override
  Future<void> initialize() async {
    await _service.initialize();
  }

  @override
  ScriptureFilterState get initialFilterState =>
      const ScriptureFilterState(activeVersionId: 'WEB');

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
                  onFilterChanged(
                    filterState.copyWith(activeVersionId: newVersionId),
                  );
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
                  onFilterChanged(
                      filterState.copyWith(fontSizeScale: newScale));
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
                  onFilterChanged(
                      filterState.copyWith(fontSizeScale: newScale));
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
        onTap: () => shareCard(context, item, repaintBoundaryKey),
      ),

      // 2. Style & Theme Studio
      CardActionButton(
        icon: Icons.palette_outlined,
        label: 'Style',
        onTap: () {
          // Quick cycle background preset on single tap
          final presets = ScriptureThemeCatalog.presets;
          final currentIndex = presets.indexWhere((p) => p.id == item.activeBackground);
          final nextIndex = (currentIndex + 1) % presets.length;
          item.customBackgroundPreset = presets[nextIndex].id;
          onRefreshCard();
        },
        onLongPress: () {
          // Open full style studio sheet on long press
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (ctx) => StyleStudioSheet(
              card: item,
              filterState: filterState,
              onFilterChanged: (newState) => onRefreshCard(),
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
    );
  }
}
