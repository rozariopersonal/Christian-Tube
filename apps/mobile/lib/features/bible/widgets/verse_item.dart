import 'package:flutter/material.dart';
import '../models/bible_verse.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import 'verse_text.dart';
import 'verse_study_badge.dart';
import 'verse_study_inline.dart';

/// A single row in the bible reader's `ListView`.
///
/// Combines the verse text, the unified study badge (reference and commentary counts),
/// and inline study expansion (for verses with single reference/commentary).
class VerseItem extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onVerseTap;
  final double fontSize;

  /// The cross-references resolved for this verse.
  final List<CrossReference> crossReferences;

  /// The historical/cultural background notes resolved for this verse.
  final List<BibleBackgroundNote> backgroundNotes;

  /// Resolved verse text keyed by [CrossReference.textKey].
  final Map<String, String> resolvedTexts;

  /// Whether the inline expansion is currently open.
  final bool isInlineExpanded;

  /// Toggles the inline expansion (used when counts <= 1).
  final VoidCallback? onToggleInline;

  /// Opens the dedicated tabbed study page (0 = references tab, 1 = commentary tab).
  final void Function(int initialTab)? onOpenStudyPage;

  /// Callback when a referenced scripture is tapped.
  final void Function(CrossReference)? onReferenceTap;

  const VerseItem({
    super.key,
    required this.verse,
    required this.isSelected,
    required this.isHighlighted,
    required this.onVerseTap,
    required this.fontSize,
    this.crossReferences = const [],
    this.backgroundNotes = const [],
    this.resolvedTexts = const {},
    this.isInlineExpanded = false,
    this.onToggleInline,
    this.onOpenStudyPage,
    this.onReferenceTap,
  });

  @override
  Widget build(BuildContext context) {
    final refCount = crossReferences.length;
    final commentaryCount = backgroundNotes.length;
    final hasStudyContent = refCount > 0 || commentaryCount > 0;
    final canExpandInline = refCount <= 1 && commentaryCount <= 1;

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

        // Unified badge with reference and commentary counts
        if (hasStudyContent) ...[
          VerseStudyBadge(
            referenceCount: refCount,
            commentaryCount: commentaryCount,
            isInlineExpanded: isInlineExpanded,
            canExpandInline: canExpandInline,
            onOpenStudyPage: (tab) => onOpenStudyPage?.call(tab),
            onToggleInline: onToggleInline ?? () {},
          ),

          // Inline expansion when there is only 1 reference and/or 1 commentary
          if (canExpandInline)
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: isInlineExpanded
                  ? VerseStudyInline(
                      references: crossReferences,
                      commentaryNotes: backgroundNotes,
                      resolvedTexts: resolvedTexts,
                      baseFontSize: fontSize,
                      onReferenceTap: onReferenceTap,
                      onOpenFullPage: onOpenStudyPage != null
                          ? () => onOpenStudyPage!(0)
                          : null,
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ],
    );
  }
}
