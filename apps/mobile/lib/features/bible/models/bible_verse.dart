class BibleVerse {
  final int number;
  final String text;
  final int? endNumber;
  final String? verseSpan;
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
    this.endNumber,
    this.verseSpan,
    this.isChapterHeader = false,
    this.chapterTitle,
    this.versionLabel,
    this.isSecondary = false,
    this.crossReferenceCount = 0,
  });

  /// The formatted display string for the verse number or combined verse span
  /// (e.g. '9-11' or '9').
  String get verseDisplay =>
      verseSpan ?? (endNumber != null && endNumber! > number ? '$number-$endNumber' : '$number');
}
