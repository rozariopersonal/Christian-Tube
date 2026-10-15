import 'dart:ui';
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
  final VoidCallback? onClear;
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
    this.onClear,
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

    // Glass effect using the active theme accent color with backdrop blur
    final accentColor = context.accent;
    final glassColor = accentColor.withValues(alpha: isDark ? 0.70 : 0.75);
    final textCol = colorScheme.onPrimary;

    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: isDark ? 0.35 : 0.15),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            color: glassColor,
            child: Material(
              color: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final actionCount = onStudy != null ? 6 : 5;
                  // Usable width inside the bar (minus horizontal padding)
                  final availableWidth = (constraints.maxWidth - 16).clamp(0.0, 520.0);
                  // Calculate item width so all actions fit on screen without scrolling
                  // Clamped to max 66.0 so they don't grow too large on tablets/wide screens
                  final itemWidth = (availableWidth / actionCount).clamp(40.0, 66.0);
                  // Dynamic icon and font sizes proportional to the item width
                  final iconSize = (itemWidth * 0.36).clamp(16.0, 21.0);
                  final fontSize = (itemWidth * 0.19).clamp(9.5, 11.5);

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ActionItem(
                            icon: Icons.copy_rounded,
                            label: 'Copy',
                            textColor: textCol,
                            width: itemWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            onPressed: onCopy,
                          ),
                          _ActionItem(
                            icon: Icons.ios_share_rounded,
                            label: 'Share',
                            textColor: textCol,
                            width: itemWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            onPressed: onShare,
                          ),
                          _ActionItem(
                            icon: Icons.bookmark_add_outlined,
                            label: 'Bookmark',
                            textColor: textCol,
                            width: itemWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            onPressed: onBookmark,
                          ),
                          _ActionItem(
                            icon: Icons.border_color_rounded,
                            label: 'Highlight',
                            textColor: textCol,
                            width: itemWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            onPressed: onHighlight,
                          ),
                          _ActionItem(
                            icon: Icons.edit_note_rounded,
                            label: 'Note',
                            textColor: textCol,
                            width: itemWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            onPressed: onNote,
                          ),
                          if (onStudy != null)
                            _ActionItem(
                              icon: Icons.auto_stories_outlined,
                              label: 'Study',
                              textColor: textCol,
                              width: itemWidth,
                              iconSize: iconSize,
                              fontSize: fontSize,
                              onPressed: onStudy!,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
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
    required this.width,
    required this.iconSize,
    required this.fontSize,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final VoidCallback onPressed;
  final double width;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: iconSize),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
