import 'package:flutter/material.dart';
import '../../core/color_utils.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/highlight_palette.dart';

/// A color/action selected from a [HighlightColorPicker].
///
/// [HighlightColorPicker.show] returns this. When the user taps a swatch,
/// [HighlightPickerPicked.colorIndex] is set. When they tap "Remove",
/// [HighlightPickerRemoved] is returned.
sealed class HighlightPickerResult {
  const HighlightPickerResult();
}

class HighlightPickerPicked extends HighlightPickerResult {
  final int colorIndex;
  const HighlightPickerPicked(this.colorIndex);
}

class HighlightPickerRemoved extends HighlightPickerResult {
  const HighlightPickerRemoved();
}

/// Reusable modal that lets the user pick from a 3×5 grid of highlight colors,
/// or remove the existing highlight.
///
/// This is agnostic to the underlying text surface (Bible verses, book lines,
/// articles…). Pass optional [titles] (e.g. `['Verse 3:16-18', 'Chapter 2']`)
/// so the picker can show a contextual label, and [hasHighlight] so the
/// "Remove" action is offered.
///
/// Use [HighlightColorPicker.show] which routes to a compact bottom sheet or a
/// centered sheet on `medium`+ screens, honoring the app's responsive rules.
class HighlightColorPicker extends StatelessWidget {
  final List<String>? titles;
  final int? currentColorIndex;
  final bool hasHighlight;
  final void Function(int colorIndex) onSelectColor;
  final VoidCallback? onRemove;

  const HighlightColorPicker({
    super.key,
    this.titles,
    this.currentColorIndex,
    this.hasHighlight = false,
    required this.onSelectColor,
    this.onRemove,
  });

  /// Shows the picker and resolves the user's choice.
  ///
  /// Returns [HighlightPickerPicked] when a color is chosen,
  /// [HighlightPickerRemoved] when the highlight is removed, or `null` when the
  /// user dismisses without choosing.
  static Future<HighlightPickerResult?> show(
    BuildContext context, {
    List<String>? titles,
    int? currentColorIndex,
    bool hasHighlight = false,
  }) async {
    HighlightPickerResult? result;
    await showAdaptiveBottomSheet<HighlightPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => HighlightColorPicker(
        titles: titles,
        currentColorIndex: currentColorIndex,
        hasHighlight: hasHighlight,
        onSelectColor: (i) {
          result = HighlightPickerPicked(i);
          Navigator.pop(sheetContext);
        },
        onRemove: hasHighlight
            ? () {
                result = const HighlightPickerRemoved();
                Navigator.pop(sheetContext);
              }
            : null,
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textCol = tokens.onSurface;
    final mutedCol = tokens.onSurfaceMuted;
    final borderCol = tokens.surfaceBorder;

    final t = titles;
    final title = t == null || t.isEmpty
        ? 'Highlight'
        : t.length == 1
            ? 'Highlight: ${t.first}'
            : 'Highlight (${t.length} items)';

    return Material(
      color: tokens.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textCol,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close, color: mutedCol, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hasHighlight
                    ? 'Pick a new color, or remove the current highlight.'
                    : 'Pick a color for the selected text.',
                style: TextStyle(color: mutedCol, fontSize: 13),
              ),
              const SizedBox(height: 16),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 72,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                children: [
                  for (var i = 0; i < HighlightPalette.count; i++)
                    _ColorSwatch(
                      color: HighlightPalette.colorFor(i),
                      selected: currentColorIndex == i,
                      onTap: () => onSelectColor(i),
                    ),
                ],
              ),
              if (hasHighlight && onRemove != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRemove,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: mutedCol,
                    side: BorderSide(color: borderCol),
                  ),
                  icon: const Icon(Icons.format_color_reset, size: 18),
                  label: const Text('Remove highlight'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = contrastColor(color);
    return Semantics(
      label: 'Highlight color',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(
                      color: onColor == const Color(0xFFFFFFFF)
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      width: 3,
                    )
                  : null,
            ),
            child: selected
                ? Icon(Icons.check, color: onColor, size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}
