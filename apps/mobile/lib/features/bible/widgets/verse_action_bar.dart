import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class VerseActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final VoidCallback? onStudy;

  const VerseActionBar({
    super.key,
    required this.selectedCount,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    this.onStudy,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Deselect all',
              icon: Icon(Icons.close, color: tokens.onSurfaceMuted),
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                '$selectedCount selected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            if (onStudy != null)
              IconButton(
                tooltip: 'Study verse',
                icon: Icon(Icons.auto_stories_outlined, color: tokens.accent),
                onPressed: onStudy,
              ),
            IconButton(
              tooltip: 'Bookmark',
              icon: Icon(Icons.bookmark_add_outlined,
                  color: tokens.onSurfaceMuted),
              onPressed: onBookmark,
            ),
            IconButton(
              tooltip: 'Share',
              icon: Icon(Icons.share_outlined, color: tokens.onSurfaceMuted),
              onPressed: onShare,
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
