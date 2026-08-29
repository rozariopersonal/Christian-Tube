import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/scripture_card.dart';
import '../models/scripture_theme_state.dart';
import '../services/bible_download_manager.dart';
import '../services/saved_scripture_service.dart';
import '../services/scripture_image_exporter.dart';
import '../widgets/scripture_share_modal.dart';

class SavedScripturesScreen extends StatefulWidget {
  const SavedScripturesScreen({super.key});

  @override
  State<SavedScripturesScreen> createState() => _SavedScripturesScreenState();
}

class _SavedScripturesScreenState extends State<SavedScripturesScreen> {
  final SavedScriptureService _savedService = SavedScriptureService();
  List<ScriptureCard> _cards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    await _savedService.initialize();
    if (mounted) {
      setState(() {
        _cards = _savedService.getSavedCards();
        _isLoading = false;
      });
    }
  }

  Future<void> _removeCard(ScriptureCard card) async {
    await _savedService.removeCard(card.id);
    _loadSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed ${card.referenceLabel} from saved'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClearAll() async {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surface,
        title: Text('Clear All Saved Scriptures?', style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove all saved verses and bookmarks?',
          style: TextStyle(color: tokens.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: tokens.onSurfaceMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _savedService.clearAll();
      _loadSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.bookmark_rounded, color: tokens.accent, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Saved Scriptures',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_cards.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_cards.length}',
                  style: TextStyle(
                    color: tokens.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_cards.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: tokens.onSurfaceMuted),
              tooltip: 'Clear All',
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final card = _cards[index];
                    return _buildSavedCard(context, card);
                  },
                ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final tokens = context.tokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bookmark_border_rounded,
                size: 56,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Saved Verses Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When you find inspiring verses in the Words feed, tap the Save bookmark icon to keep them in your personal favorites collection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: tokens.onSurfaceMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedCard(BuildContext context, ScriptureCard card) {
    final tokens = context.tokens;
    final preset = ScriptureThemeCatalog.getPreset(card.activeBackground);
    final version = card.resolvedVersion ?? BibleDownloadManager.defaultVersionId;
    final verseText = card.resolvedText ??
        '“Peace I leave with you; my peace I give you. Do not let your hearts be troubled.”';

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tokens.surfaceBorder,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: tokens.isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        version,
                        style: TextStyle(
                          color: tokens.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      card.referenceLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: tokens.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Verse Body Text
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              verseText,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: tokens.isDark
                    ? tokens.onSurface.withValues(alpha: 0.95)
                    : tokens.onSurface,
              ),
            ),
          ),

          // Action Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Copy Action
                TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.onSurfaceMuted,
                  ),
                  onPressed: () async {
                    final textToCopy = '“$verseText”\n\n— ${card.referenceLabel} ($version)';
                    await Clipboard.setData(ClipboardData(text: textToCopy));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Scripture copied to clipboard!'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),

                // Share Image Action
                TextButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share Graphic', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.accent,
                  ),
                  onPressed: () async {
                    try {
                      final pngBytes = await ScriptureGraphicGenerator.generateStoryImage(
                        card: card,
                        activeVersionId: version,
                        fontFamily: 'Playfair',
                        fontSizeScale: 1.0,
                        textColorHex: '#FFFFFF',
                      );
                      if (context.mounted) {
                        ScriptureShareModal.show(
                          context,
                          imageBytes: pngBytes,
                          card: card,
                          fileName: '${card.bookName}_${card.chapter}_${card.startVerse}.png',
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to export graphic: $e')),
                        );
                      }
                    }
                  },
                ),

                // Delete Action
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: Theme.of(context).colorScheme.error),
                  tooltip: 'Remove',
                  onPressed: () => _removeCard(card),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
