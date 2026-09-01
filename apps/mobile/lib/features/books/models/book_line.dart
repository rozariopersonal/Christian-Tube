class BookLine {
  final String bookId;
  final int pageNumber;
  final int lineNumber;
  final int chapterIndex;
  final String contentType;
  final String text;

  const BookLine({
    required this.bookId,
    required this.pageNumber,
    required this.lineNumber,
    required this.chapterIndex,
    this.contentType = 'p',
    required this.text,
  });

  factory BookLine.fromMap(Map<String, dynamic> map) {
    return BookLine(
      bookId: (map['book_id'] ?? map['bookId']) as String? ?? '',
      pageNumber: ((map['page_number'] ?? map['pageNumber'] ?? map['page']) as num?)?.toInt() ?? 1,
      lineNumber: ((map['line_number'] ?? map['lineNumber'] ?? map['line']) as num?)?.toInt() ?? 1,
      chapterIndex: ((map['chapter_index'] ?? map['chapterIndex'] ?? map['chapter']) as num?)?.toInt() ?? 1,
      contentType: (map['content_type'] ?? map['contentType'] ?? map['type']) as String? ?? 'p',
      text: map['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'book_id': bookId,
      'page_number': pageNumber,
      'line_number': lineNumber,
      'chapter_index': chapterIndex,
      'content_type': contentType,
      'text': text,
    };
  }
}
