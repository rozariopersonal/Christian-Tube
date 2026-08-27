import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scripture_card.dart';
import '../models/scripture_theme_state.dart';
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Clear All Saved Scriptures?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to remove all saved verses and bookmarks?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B), size: 22),
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
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_cards.length}',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
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
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
              tooltip: 'Clear All',
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final card = _cards[index];
                    return _buildSavedCard(context, card, isDark);
                  },
                ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_border_rounded,
                size: 56,
                color: Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Saved Verses Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When you find inspiring verses in the Words feed, tap the Save bookmark icon to keep them in your personal favorites collection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedCard(BuildContext context, ScriptureCard card, bool isDark) {
    final preset = ScriptureThemeCatalog.getPreset(card.activeBackground);
    final version = card.resolvedVersion ?? 'WEB';
    final verseText = card.resolvedText ??
        '“Peace I leave with you; my peace I give you. Do not let your hearts be troubled.”';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
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
              color: isDark ? Colors.black26 : const Color(0xFFF1F5F9),
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
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        version,
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
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
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
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
                color: isDark ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF1E293B),
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
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
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
                    foregroundColor: const Color(0xFFF59E0B),
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
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
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
