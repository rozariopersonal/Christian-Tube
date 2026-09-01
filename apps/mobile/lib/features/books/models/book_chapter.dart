class BookChapter {
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final int startPage;
  final int startLine;
  final int endPage;
  final int endLine;

  const BookChapter({
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.startPage,
    required this.startLine,
    required this.endPage,
    required this.endLine,
  });

  factory BookChapter.fromMap(Map<String, dynamic> map) {
    return BookChapter(
      bookId: map['book_id'] as String? ?? '',
      chapterIndex: (map['chapter_index'] as num?)?.toInt() ?? 1,
      chapterTitle: map['chapter_title'] as String? ?? '',
      startPage: (map['start_page'] as num?)?.toInt() ?? 1,
      startLine: (map['start_line'] as num?)?.toInt() ?? 1,
      endPage: (map['end_page'] as num?)?.toInt() ?? 1,
      endLine: (map['end_line'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'chapter_title': chapterTitle,
      'start_page': startPage,
      'start_line': startLine,
      'end_page': endPage,
      'end_line': endLine,
    };
  }
}
