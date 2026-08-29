import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class VerseActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;

  const VerseActionBar({
    super.key,
    required this.selectedCount,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.close, color: tokens.onSurfaceMuted),
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                '$selectedCount selected',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Share',
              icon: Icon(Icons.share, color: tokens.onSurfaceMuted),
              onPressed: onShare,
            ),
            IconButton(
              tooltip: 'Bookmark',
              icon: Icon(Icons.bookmark_add_outlined,
                  color: tokens.onSurfaceMuted),
              onPressed: onBookmark,
            ),
            ElevatedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onSurface,
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
