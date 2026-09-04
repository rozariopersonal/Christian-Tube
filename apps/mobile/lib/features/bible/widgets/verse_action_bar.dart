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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 360;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 16, vertical: 8),
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
        padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Deselect all',
              padding: isNarrow ? EdgeInsets.zero : const EdgeInsets.all(8),
              constraints: isNarrow ? const BoxConstraints.tightFor(width: 32, height: 32) : null,
              icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: isNarrow ? 18 : 22),
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                isNarrow ? '$selectedCount' : '$selectedCount selected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: isNarrow ? 13 : 14,
                ),
              ),
            ),
            if (onStudy != null)
              IconButton(
                tooltip: 'Study verse',
                padding: isNarrow ? EdgeInsets.zero : const EdgeInsets.all(8),
                constraints: isNarrow ? const BoxConstraints.tightFor(width: 32, height: 32) : null,
                icon: Icon(Icons.auto_stories_outlined, color: tokens.accent, size: isNarrow ? 18 : 22),
                onPressed: onStudy,
              ),
            IconButton(
              tooltip: 'Bookmark',
              padding: isNarrow ? EdgeInsets.zero : const EdgeInsets.all(8),
              constraints: isNarrow ? const BoxConstraints.tightFor(width: 32, height: 32) : null,
              icon: Icon(Icons.bookmark_add_outlined,
                  color: tokens.onSurfaceMuted, size: isNarrow ? 18 : 22),
              onPressed: onBookmark,
            ),
            IconButton(
              tooltip: 'Share',
              padding: isNarrow ? EdgeInsets.zero : const EdgeInsets.all(8),
              constraints: isNarrow ? const BoxConstraints.tightFor(width: 32, height: 32) : null,
              icon: Icon(Icons.share_outlined, color: tokens.onSurfaceMuted, size: isNarrow ? 18 : 22),
              onPressed: onShare,
            ),
            SizedBox(width: isNarrow ? 2 : 4),
            isNarrow
                ? IconButton.filled(
                    tooltip: 'Copy',
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.onSurface,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                    ),
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                  )
                : ElevatedButton.icon(
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
