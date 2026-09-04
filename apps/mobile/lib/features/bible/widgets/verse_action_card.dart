import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class VerseActionCard extends StatelessWidget {
  final int selectedCount;
  final int referenceCount;
  final int commentaryCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final void Function(int tab)? onOpenStudyPage;

  const VerseActionCard({
    super.key,
    required this.selectedCount,
    required this.referenceCount,
    required this.commentaryCount,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    this.onOpenStudyPage,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Study Chips Row
          if (referenceCount > 0 || commentaryCount > 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (referenceCount > 0)
                  ActionChip(
                    avatar: Icon(Icons.link_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                    label: Text(
                      '$referenceCount Reference${referenceCount > 1 ? 's' : ''}',
                      style: TextStyle(color: tokens.onSurface),
                    ),
                    backgroundColor: tokens.surface,
                    side: BorderSide(color: tokens.surfaceBorder),
                    onPressed: () => onOpenStudyPage?.call(1),
                  ),
                if (commentaryCount > 0)
                  ActionChip(
                    avatar: Icon(Icons.menu_book_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                    label: Text(
                      '$commentaryCount ${commentaryCount > 1 ? 'Commentaries' : 'Commentary'}',
                      style: TextStyle(color: tokens.onSurface),
                    ),
                    backgroundColor: tokens.surface,
                    side: BorderSide(color: tokens.surfaceBorder),
                    onPressed: () => onOpenStudyPage?.call(2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: tokens.surfaceBorder, height: 1),
            const SizedBox(height: 8),
          ],
          
          // Action Buttons Row
          Row(
            children: [
              if (selectedCount > 1) ...[
                Text(
                  '$selectedCount selected',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
              ],
              if (selectedCount <= 1) const Spacer(),
              IconButton(
                tooltip: 'Share',
                icon: Icon(Icons.share, color: tokens.onSurfaceMuted, size: 20),
                onPressed: onShare,
              ),
              IconButton(
                tooltip: 'Bookmark',
                icon: Icon(Icons.bookmark_add_outlined, color: tokens.onSurfaceMuted, size: 20),
                onPressed: onBookmark,
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
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
