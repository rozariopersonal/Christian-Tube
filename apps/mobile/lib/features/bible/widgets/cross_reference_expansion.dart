import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/adaptivity.dart';
import '../models/cross_reference.dart';
import 'cross_reference_card.dart';

/// The inline expandable cross-reference section shown below a verse.
///
/// Caps the visible cards by screen size (compact 6, medium 8, expanded 10)
/// with a "Show all N" / "Show fewer" toggle. Owns its own truncated-vs-full
/// state so the parent (a `ListView` item) only has to mount/unmount it —
/// the item count never changes, only the height of this widget.
class CrossReferenceExpansion extends StatefulWidget {
  final List<CrossReference> references;
  final Map<String, String> resolvedTexts;
  final double baseFontSize;
  final void Function(CrossReference) onTapReference;

  const CrossReferenceExpansion({
    super.key,
    required this.references,
    required this.resolvedTexts,
    required this.baseFontSize,
    required this.onTapReference,
  });

  @override
  State<CrossReferenceExpansion> createState() =>
      _CrossReferenceExpansionState();
}

class _CrossReferenceExpansionState extends State<CrossReferenceExpansion> {
  bool _showAll = false;

  int get _maxVisible {
    switch (ScreenClass.of(context)) {
      case ScreenClass.compact:
        return 6;
      case ScreenClass.medium:
        return 8;
      case ScreenClass.expanded:
        return 10;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final references = widget.references;
    final maxVisible = _maxVisible;
    final hasMore = references.length > maxVisible;
    final visible = hasMore && !_showAll
        ? references.sublist(0, maxVisible)
        : references;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ref in visible)
              CrossReferenceCard(
                reference: ref,
                text: widget.resolvedTexts[ref.textKey],
                fontSize: widget.baseFontSize,
                onTap: () => widget.onTapReference(ref),
              ),
            if (hasMore) ...[
              const SizedBox(height: 2),
              InkWell(
                onTap: () => setState(() => _showAll = !_showAll),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showAll
                            ? 'Show fewer'
                            : 'Show all ${references.length} references',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _showAll
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: tokens.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
