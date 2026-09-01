import 'package:flutter/material.dart';
import '../../../core/layout/adaptivity.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_background_note.dart';

/// Modal bottom sheet displaying historical and cultural background notes for
/// a selected Bible verse or chapter.
///
/// Follows the repository's Responsive & Adaptive UI Standard:
/// - Max width capped at 640px and centered on larger displays.
/// - Scrollable internal body with no fixed container heights.
/// - Strict use of design tokens (AppTokens / context.tokens).
class BibleBackgroundSheet extends StatelessWidget {
  final String verseLabel;
  final String verseText;
  final List<BibleBackgroundNote> notes;

  const BibleBackgroundSheet({
    super.key,
    required this.verseLabel,
    required this.verseText,
    required this.notes,
  });

  static Future<void> show({
    required BuildContext context,
    required String verseLabel,
    required String verseText,
    required List<BibleBackgroundNote> notes,
  }) {
    final screen = ScreenClass.of(context);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screen.isCompact ? double.infinity : 640,
          ),
          child: BibleBackgroundSheet(
            verseLabel: verseLabel,
            verseText: verseText,
            notes: notes,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.history_edu, color: tokens.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Historical & Cultural Context',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        verseLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: tokens.onSurfaceMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable content
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Verse preview box
                if (verseText.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(color: tokens.accent, width: 3),
                      ),
                    ),
                    child: Text(
                      verseText,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_outlined,
                              size: 48, color: tokens.onSurfaceMuted),
                          const SizedBox(height: 12),
                          Text(
                            'No specific cultural notes for this verse',
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...notes.map((note) => _buildNoteCard(context, note)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, BibleBackgroundNote note) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic header & attribution pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  note.topic,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  note.isChapterOverview ? 'Overview' : 'Context',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          if (note.quote != null && note.quote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Quote: "${note.quote}"',
                style: TextStyle(
                  color: tokens.onSurfaceMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Context explanation
          Text(
            note.text,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: 14,
              height: 1.55,
            ),
          ),

          const SizedBox(height: 10),

          // Source attribution footer
          Row(
            children: [
              Icon(Icons.verified_outlined,
                  size: 13, color: tokens.onSurfaceMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  note.source,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
