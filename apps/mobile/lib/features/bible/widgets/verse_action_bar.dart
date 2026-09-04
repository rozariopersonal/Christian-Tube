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
      decoration: BoxDecoration(
        color: tokens.surface,
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Selection count and Clear
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Deselect all',
                    icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                    onPressed: onClear,
                  ),
                  Expanded(
                    child: Text(
                      '$selectedCount selected',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom row: Actions
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionItem(
                    icon: Icons.copy,
                    label: 'Copy',
                    onPressed: onCopy,
                  ),
                  _ActionItem(
                    icon: Icons.ios_share,
                    label: 'Share',
                    onPressed: onShare,
                  ),
                  _ActionItem(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Bookmark',
                    onPressed: onBookmark,
                  ),
                  if (onStudy != null)
                    _ActionItem(
                      icon: Icons.auto_stories_outlined,
                      label: 'Study',
                      onPressed: onStudy!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tokens.onSurface, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
