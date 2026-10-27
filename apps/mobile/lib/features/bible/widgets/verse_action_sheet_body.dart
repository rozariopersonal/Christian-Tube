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
      padding: const EdgeInsets.fromLTRB(AppDimens.lg, AppDimens.xs, AppDimens.lg, AppDimens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
          const SizedBox(height: 4),
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
                  icon: const Icon(Icons.format_color_reset, size: 16),
                  label: const Text('Remove highlight'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    textStyle: textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
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
    return Tooltip(
      message: HighlightPalette.nameFor(i),
      child: Semantics(
        label: 'Highlight color',
        button: true,
        selected: currentColorIndex == i,
        child: InkResponse(
          onTap: () => onHighlightColor != null
              ? onHighlightColor!(i)
              : onHighlight(),
          radius: AppDimens.lg,
          child: SizedBox.square(
            dimension: 38,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: HighlightPalette.colorFor(i),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: currentColorIndex == i
                        ? tokens.onSurface
                        : tokens.surfaceBorder,
                    width: currentColorIndex == i ? 1.5 : 1.0,
                  ),
                ),
                child: currentColorIndex == i
                    ? Icon(
                        Icons.check,
                        size: 16,
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
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: tokens.onSurface),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
