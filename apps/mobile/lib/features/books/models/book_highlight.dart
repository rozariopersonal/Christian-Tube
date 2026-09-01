class BookHighlight {
  final String id;
  final String bookId;
  final int chapterIndex;
  final int pageNumber;
  final int startChar;
  final int endChar;
  final String text;
  final int color; // 0 = Yellow, 1 = Green, 2 = Blue, 3 = Pink
  final String createdAt;

  const BookHighlight({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.pageNumber,
    required this.startChar,
    required this.endChar,
    required this.text,
    this.color = 0,
    required this.createdAt,
  });

  factory BookHighlight.fromMap(Map<String, dynamic> map) {
    return BookHighlight(
      id: map['id'] as String? ?? '',
      bookId: map['book_id'] as String? ?? '',
      chapterIndex: (map['chapter_index'] as num?)?.toInt() ?? 1,
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      startChar: (map['start_char'] as num?)?.toInt() ?? 0,
      endChar: (map['end_char'] as num?)?.toInt() ?? 0,
      text: map['text'] as String? ?? '',
      color: (map['color'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'page_number': pageNumber,
      'start_char': startChar,
      'end_char': endChar,
      'text': text,
      'color': color,
      'created_at': createdAt,
    };
  }
}
