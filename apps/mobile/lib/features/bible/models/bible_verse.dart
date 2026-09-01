class BibleVerse {
  final int number;
  final String text;
  final bool isChapterHeader;
  final String? chapterTitle;
  final String? versionLabel;
  final bool isSecondary;

  /// Number of cross-references for this verse. 0 hides the cross-reference
  /// badge and expansion; >0 shows a badge and enables inline expansion.
  final int crossReferenceCount;

  BibleVerse({
    required this.number,
    required this.text,
    this.isChapterHeader = false,
    this.chapterTitle,
    this.versionLabel,
    this.isSecondary = false,
    this.crossReferenceCount = 0,
  });
}
