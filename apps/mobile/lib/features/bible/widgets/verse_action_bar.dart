import 'package:flutter/material.dart';

import '../../../shared/ui/floating_selection_bar.dart';

/// Floating, single-line verse action bar for the Bible reader.
///
/// `[ ● ● ● ⌄ ] | Bookmark  Share  Study  ⋯(Copy, Note)`
///
/// The three swatches are the user's most-used highlight colours; the chevron
/// expands the full palette in place. Rendered by the reader screen above the
/// list (not inline), so it never scrolls with the verses.
class VerseActionBar extends StatelessWidget {
  const VerseActionBar({
    super.key,
    this.selectedCount = 1,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onNote,
    required this.onHighlightColor,
    this.onRemoveHighlight,
    this.onClear,
    this.onStudy,
    this.currentColorIndex,
    this.hasHighlight = false,
    this.isBookmarked = false,
    this.expandBelow = false,
  });

  final int selectedCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onNote;
  final ValueChanged<int> onHighlightColor;
  final VoidCallback? onRemoveHighlight;
  final VoidCallback? onClear;
  final VoidCallback? onStudy;
  final int? currentColorIndex;
  final bool hasHighlight;
  final bool isBookmarked;
  final bool expandBelow;

  static const bookmarkKey = Key('verse_bar_bookmark');
  static const shareKey = Key('verse_bar_share');
  static const studyKey = Key('verse_bar_study');

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();
    return FloatingSelectionBar(
      countBadge: selectedCount,
      expandBelow: expandBelow,
      currentColorIndex: currentColorIndex,
      hasHighlight: hasHighlight,
      onSwatch: onHighlightColor,
      onClearHighlight: onRemoveHighlight,
      onDismiss: onClear,
      actions: [
        SelectionBarAction(
          key: bookmarkKey,
          icon: isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_add_outlined,
          tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
          isActive: isBookmarked,
          onTap: onBookmark,
        ),
        SelectionBarAction(
          key: shareKey,
          icon: Icons.ios_share_rounded,
          tooltip: 'Share',
          onTap: onShare,
        ),
        if (onStudy != null)
          SelectionBarAction(
            key: studyKey,
            icon: Icons.auto_stories_outlined,
            tooltip: 'Bible study',
            onTap: onStudy!,
          ),
      ],
      overflow: [
        SelectionBarMenuItem(
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: onCopy,
        ),
        SelectionBarMenuItem(
          icon: Icons.edit_note_rounded,
          label: 'Note',
          onTap: onNote,
        ),
      ],
    );
  }
}
