class BibleVerse {
  final int number;
  final String text;
  final bool isChapterHeader;
  final String? chapterTitle;

  BibleVerse({
    required this.number,
    required this.text,
    this.isChapterHeader = false,
    this.chapterTitle,
  });
}
