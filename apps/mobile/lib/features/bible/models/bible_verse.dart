class BibleVerse {
  final int number;
  final String text;
  final bool isChapterHeader;
  final String? chapterTitle;
  final String? versionLabel;
  final bool isSecondary;

  BibleVerse({
    required this.number,
    required this.text,
    this.isChapterHeader = false,
    this.chapterTitle,
    this.versionLabel,
    this.isSecondary = false,
  });
}
