import 'package:flutter/material.dart';

import '../../../core/dimens.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/highlight_palette.dart';

/// Scrollable verse actions and palette, independent of sheet motion.
class VerseActionSheetBody extends StatelessWidget {
  const VerseActionSheetBody({
    super.key,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onNote,
    required this.onHighlight,
    this.onHighlightColor,
    this.onRemoveHighlight,
    this.currentColorIndex,
    this.hasHighlight = false,
    this.isBookmarked = false,
  });

  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onNote;
  final VoidCallback onHighlight;
  final ValueChanged<int>? onHighlightColor;
  final VoidCallback? onRemoveHighlight;
  final int? currentColorIndex;
  final bool hasHighlight;
  final bool isBookmarked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.lg,
        AppDimens.xs,
        AppDimens.lg,
        AppDimens.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: tokens.surfaceVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              border: Border.all(
                color: tokens.surfaceBorder.withValues(alpha: 0.6),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: _Action(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: onShare,
                  ),
                ),
                Expanded(
                  child: _Action(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: onCopy,
                  ),
                ),
                Expanded(
                  child: _Action(
                    icon: isBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_add_outlined,
                    label: isBookmarked ? 'Bookmarked' : 'Bookmark',
                    isActive: isBookmarked,
                    onTap: onBookmark,
                  ),
                ),
                Expanded(
                  child: _Action(
                    icon: Icons.edit_note_rounded,
                    label: 'Note',
                    onTap: onNote,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppDimens.sm,
            runSpacing: AppDimens.xs,
            children: [
              Text(
                'Highlight',
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.onSurfaceMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              if (hasHighlight && onRemoveHighlight != null)
                TextButton.icon(
                  onPressed: onRemoveHighlight,
                  icon: const Icon(Icons.format_color_reset, size: 15),
                  label: const Text('Remove highlight'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: tokens.onSurfaceMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    textStyle: textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                border: Border.all(
                  color: tokens.surfaceBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 3; row++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var col = 0; col < 5; col++)
                            _buildColorItem(context, row * 5 + col, tokens),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorItem(BuildContext context, int i, AppTokens tokens) {
    final isSelected = currentColorIndex == i;
    final color = HighlightPalette.colorFor(i);
    return Tooltip(
      message: HighlightPalette.nameFor(i),
      child: Semantics(
        label: 'Highlight color',
        button: true,
        selected: isSelected,
        child: InkResponse(
          onTap: () => onHighlightColor != null
              ? onHighlightColor!(i)
              : onHighlight(),
          radius: AppDimens.md,
          child: SizedBox.square(
            dimension: 36,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                  border: Border.all(
                    color: isSelected
                        ? tokens.onSurface
                        : tokens.surfaceBorder.withValues(alpha: 0.7),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 15,
                        color: HighlightPalette.onColorFor(i),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = context.accent;
    final fgColor = isActive ? accent : tokens.onSurface;
    final bgColor =
        isActive ? accent.withValues(alpha: 0.12) : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fgColor),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: fgColor,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
