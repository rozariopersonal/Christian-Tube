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
  final EdgeInsetsGeometry? margin;

  const VerseActionBar({
    super.key,
    this.selectedCount = 1,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onHighlight,
    required this.onNote,
    required this.onClear,
    this.onStudy,
    this.appearance,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark ||
        (appearance?.isDark(tokens) ?? false);

    // Floating bar has a distinct background color contrasting with the
    // reader background and the main navigation bar tabs below.
    final bg = isDark
        ? tokens.surfaceElevated
        : colorScheme.surfaceContainerHighest;
    final textCol = isDark ? tokens.onSurface : colorScheme.onSurface;
    final mutedCol = isDark ? tokens.onSurfaceMuted : colorScheme.onSurfaceVariant;
    final borderCol = tokens.surfaceBorder;

    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderCol.withValues(alpha: isDark ? 0.25 : 0.45),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionItem(
                        icon: Icons.copy_rounded,
                        label: 'Copy',
                        textColor: textCol,
                        onPressed: onCopy,
                      ),
                      _ActionItem(
                        icon: Icons.ios_share_rounded,
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
              Container(
                height: 28,
                width: 1,
                color: borderCol.withValues(alpha: isDark ? 0.25 : 0.4),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: IconButton(
                  tooltip: 'Deselect all',
                  icon: Icon(Icons.close_rounded, color: mutedCol, size: 20),
                  onPressed: onClear,
                ),
              ),
            ],
          ),
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
      width: 62,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(height: 3),
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
