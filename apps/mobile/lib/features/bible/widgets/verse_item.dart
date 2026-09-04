import 'package:flutter/material.dart';
import '../../../shared/services/reader_appearance.dart';
import '../models/bible_verse.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import 'verse_text.dart';

/// A single row in the bible reader's `ListView`.
///
/// Combines the verse text, superscript study icons, and an inline Action Card.
class VerseItem extends StatelessWidget {
  final BibleVerse verse;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onVerseTap;
  final ReaderAppearance appearance;

  /// The cross-references resolved for this verse.
  final List<CrossReference> crossReferences;

  /// The historical/cultural background notes resolved for this verse.
  final List<BibleBackgroundNote> backgroundNotes;

  /// Resolved verse text keyed by [CrossReference.textKey].
  final Map<String, String> resolvedTexts;

  /// Number of verses currently selected.
  final int selectedCount;
  
  /// Actions for the action card.
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;
  final VoidCallback? onClear;
  final void Function(int initialTab)? onOpenStudyPage;

  const VerseItem({
    super.key,
    required this.verse,
    required this.isSelected,
    required this.isHighlighted,
    required this.onVerseTap,
    required this.appearance,
    this.crossReferences = const [],
    this.backgroundNotes = const [],
    this.resolvedTexts = const {},
    this.selectedCount = 0,
    this.onCopy,
    this.onShare,
    this.onBookmark,
    this.onClear,
    this.onOpenStudyPage,
  });

  @override
  Widget build(BuildContext context) {
    return VerseText(
      verse: verse,
      isSelected: isSelected,
      isHighlighted: isHighlighted,
      onTap: onVerseTap,
      appearance: appearance,
      refCount: crossReferences.length,
      commentaryCount: backgroundNotes.length,
    );
  }
}
