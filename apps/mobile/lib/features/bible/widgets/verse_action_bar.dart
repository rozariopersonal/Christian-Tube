import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/reader_appearance.dart';

class VerseActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback onClear;
  final VoidCallback? onStudy;
  final ReaderAppearance? appearance;

  const VerseActionBar({
    super.key,
    required this.selectedCount,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onHighlight,
    required this.onNote,
    required this.onClear,
    this.onStudy,
    this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    final tokens = context.tokens;
    final bg = appearance?.surface(tokens) ?? tokens.surface;
    final textCol = appearance?.textColor(tokens) ?? tokens.onSurface;
    final mutedCol = appearance?.mutedTextColor(tokens) ?? tokens.onSurfaceMuted;
    final borderCol = appearance?.surfaceBorder(tokens) ?? tokens.surfaceBorder;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: borderCol, width: 0.5)),
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
                    icon: Icon(Icons.close, color: mutedCol, size: 20),
                    onPressed: onClear,
                  ),
                  Expanded(
                    child: Text(
                      '$selectedCount selected',
                      style: TextStyle(
                        color: textCol,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom row: Actions — horizontally scrollable so the six items
            // never overflow at 320dp width or large text scales.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionItem(
                      icon: Icons.copy,
                      label: 'Copy',
                      textColor: textCol,
                      onPressed: onCopy,
                    ),
                    _ActionItem(
                      icon: Icons.ios_share,
                      label: 'Share',
                      textColor: textCol,
                      onPressed: onShare,
                    ),
                    _ActionItem(
                      icon: Icons.bookmark_add_outlined,
                      label: 'Bookmark',
                      textColor: textCol,
                      onPressed: onBookmark,
                    ),
                    _ActionItem(
                      icon: Icons.border_color_rounded,
                      label: 'Highlight',
                      textColor: textCol,
                      onPressed: onHighlight,
                    ),
                    _ActionItem(
                      icon: Icons.edit_note_rounded,
                      label: 'Note',
                      textColor: textCol,
                      onPressed: onNote,
                    ),
                    if (onStudy != null)
                      _ActionItem(
                        icon: Icons.auto_stories_outlined,
                        label: 'Study',
                        textColor: textCol,
                        onPressed: onStudy!,
                      ),
                  ],
                ),
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
    required this.textColor,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
