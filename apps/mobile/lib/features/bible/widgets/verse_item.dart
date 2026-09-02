import 'package:flutter/material.dart';
import '../models/bible_verse.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import 'verse_text.dart';

/// A single row in the bible reader's `ListView`.
///
/// Combines the verse text and superscript study icons.
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

  /// Whether the inline expansion is currently open. (No longer used in new UI)
  final bool isInlineExpanded;

  /// Toggles the inline expansion. (No longer used in new UI)
  final VoidCallback? onToggleInline;

  /// Opens the dedicated tabbed study page (0 = references tab, 1 = commentary tab).
  final void Function(int initialTab)? onOpenStudyPage;

  /// Callback when a referenced scripture is tapped. (No longer used in new UI)
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
          refCount: refCount,
          commentaryCount: commentaryCount,
        ),
      ],
    );
  }
}
