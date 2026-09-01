import 'package:flutter/material.dart';
import '../models/bible_verse.dart';
import '../models/cross_reference.dart';
import 'verse_text.dart';
import 'cross_reference_badge.dart';
import 'cross_reference_expansion.dart';

/// A single row in the bible reader's `ListView`.
///
/// Combines the verse text, its (optional) cross-reference badge and the
/// inline cross-reference expansion into one self-contained item. Because the
/// cross-reference section is a child of this item (rather than a separate
/// list entry), the `ListView`'s item count stays constant regardless of how
/// many verses are expanded — no scroll jumps, no builder thrash.
///
/// All cross-reference UI is hidden when [showCrossReferences] is false (e.g.
/// data not installed) or when `verse.crossReferenceCount == 0`.
class VerseItem extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onVerseTap;
  final double fontSize;

  /// Whether the embedded cross-reference UI is available at all (data
  /// installed on device).
  final bool showCrossReferences;

  /// Whether this verse's cross-reference section is currently expanded.
  final bool crossRefsExpanded;

  /// The cross-references resolved for `verse.number` (empty = none).
  final List<CrossReference> crossReferences;

  /// Resolved verse text keyed by [CrossReference.textKey].
  final Map<String, String> resolvedTexts;

  final VoidCallback? onBadgeTap;
  final void Function(CrossReference)? onReferenceTap;

  const VerseItem({
    super.key,
    required this.verse,
    required this.isSelected,
    required this.isHighlighted,
    required this.onVerseTap,
    required this.fontSize,
    this.showCrossReferences = false,
    this.crossRefsExpanded = false,
    this.crossReferences = const [],
    this.resolvedTexts = const {},
    this.onBadgeTap,
    this.onReferenceTap,
  });

  @override
  Widget build(BuildContext context) {
    final renderCrossRefs =
        showCrossReferences && verse.crossReferenceCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        VerseText(
          verse: verse,
          isSelected: isSelected,
          isHighlighted: isHighlighted,
          onTap: onVerseTap,
          fontSize: fontSize,
        ),
        if (renderCrossRefs) ...[
          CrossReferenceBadge(
            count: verse.crossReferenceCount,
            expanded: crossRefsExpanded,
            onTap: onBadgeTap ?? () {},
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: crossRefsExpanded
                ? CrossReferenceExpansion(
                    references: crossReferences,
                    resolvedTexts: resolvedTexts,
                    baseFontSize: fontSize,
                    onTapReference: onReferenceTap ?? (_) {},
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}
