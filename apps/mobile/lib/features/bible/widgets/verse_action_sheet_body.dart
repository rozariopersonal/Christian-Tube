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
      padding: const EdgeInsets.all(AppDimens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: AppDimens.sm,
            runSpacing: AppDimens.sm,
            children: [
              _Action(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: onShare),
              _Action(icon: Icons.copy_rounded, label: 'Copy', onTap: onCopy),
              _Action(
                  icon: isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_add_outlined,
                  label: isBookmarked ? 'Bookmarked' : 'Bookmark',
                  onTap: onBookmark),
              _Action(
                  icon: Icons.edit_note_rounded, label: 'Note', onTap: onNote),
            ],
          ),
          const SizedBox(height: AppDimens.sm),
          const Divider(),
          Text('Highlight', style: textTheme.labelLarge),
          const SizedBox(height: AppDimens.sm),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < HighlightPalette.count; i++)
                Tooltip(
                  message: HighlightPalette.nameFor(i),
                  child: Semantics(
                    label: 'Highlight color',
                    button: true,
                    selected: currentColorIndex == i,
                    child: InkResponse(
                      onTap: () => onHighlightColor != null
                          ? onHighlightColor!(i)
                          : onHighlight(),
                      radius: AppDimens.xl,
                      child: SizedBox.square(
                        dimension: AppDimens.minTouchTarget,
                        child: Center(
                          child: Container(
                            width: AppDimens.xxl,
                            height: AppDimens.xxl,
                            decoration: BoxDecoration(
                              color: HighlightPalette.colorFor(i),
                              shape: BoxShape.circle,
                              border: Border.all(color: tokens.surfaceBorder),
                            ),
                            child: currentColorIndex == i
                                ? Icon(Icons.check,
                                    color: HighlightPalette.onColorFor(i))
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (hasHighlight && onRemoveHighlight != null)
            TextButton.icon(
              onPressed: onRemoveHighlight,
              icon: const Icon(Icons.format_color_reset),
              label: const Text('Remove highlight'),
            ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: AppDimens.xs),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
