import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/adaptivity.dart';
import '../models/bible_verse.dart';
import '../models/cross_reference.dart';
import 'verse_text.dart';
import 'cross_reference_badge.dart';
import 'cross_reference_expansion.dart';

/// A single row in the bible reader's `ListView`.
///
/// Combines the verse text, its (optional) cross-reference badge, historical
/// context badge, and inline cross-reference expansion into one self-contained item.
class VerseItem extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onVerseTap;
  final double fontSize;

  /// Whether the cross-reference UI is available at all.
  final bool showCrossReferences;

  /// Whether this verse's cross-reference section is currently expanded.
  final bool crossRefsExpanded;

  /// The cross-references resolved for `verse.number` (empty = none).
  final List<CrossReference> crossReferences;

  /// Resolved verse text keyed by [CrossReference.textKey].
  final Map<String, String> resolvedTexts;

  final VoidCallback? onBadgeTap;
  final void Function(CrossReference)? onReferenceTap;

  /// Invoked when a verse with more than two references wants to open its
  /// dedicated cross-references page.
  final VoidCallback? onReviewPageOpen;

  /// Number of historical/cultural background notes available for this verse.
  final int backgroundNotesCount;

  /// Invoked when the historical context badge is tapped.
  final VoidCallback? onBackgroundTap;

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
    this.onReviewPageOpen,
    this.backgroundNotesCount = 0,
    this.onBackgroundTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final badgeFontSize = screen.isCompact ? 12.0 : 13.0;

    final count = verse.crossReferenceCount;
    final renderCrossRefs = showCrossReferences && count > 0;
    final openReviewPage = count > 2;
    final renderBackground = backgroundNotesCount > 0 && onBackgroundTap != null;

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
        if (renderCrossRefs || renderBackground) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (renderCrossRefs)
                  CrossReferenceBadge(
                    count: count,
                    expanded: crossRefsExpanded && !openReviewPage,
                    openPage: openReviewPage,
                    onTap: onBadgeTap ?? () {},
                  ),
                if (renderBackground)
                  Semantics(
                    label:
                        '$backgroundNotesCount historical context notes, tap to view',
                    button: true,
                    child: InkWell(
                      onTap: onBackgroundTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: tokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.surfaceBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_edu,
                              size: badgeFontSize,
                              color: tokens.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Context ($backgroundNotesCount)',
                              style: TextStyle(
                                color: tokens.onSurface,
                                fontSize: badgeFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (renderCrossRefs && !openReviewPage)
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: crossRefsExpanded
                  ? CrossReferenceExpansion(
                      references: crossReferences,
                      resolvedTexts: resolvedTexts,
                      baseFontSize: fontSize,
                      onViewAll: onReviewPageOpen,
                      onTapReference: onReferenceTap ?? (_) {},
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ],
    );
  }
}
