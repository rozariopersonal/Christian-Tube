import 'dart:convert';

class BookSubtitle {
  final String title;
  final int pageNumber;
  final int lineNumber;

  const BookSubtitle({
    required this.title,
    required this.pageNumber,
    required this.lineNumber,
  });

  factory BookSubtitle.fromMap(Map<String, dynamic> map) {
    return BookSubtitle(
      title: (map['title'] ?? map['text']) as String? ?? '',
      pageNumber: ((map['page_number'] ?? map['pageNumber'] ?? map['page']) as num?)?.toInt() ?? 1,
      lineNumber: ((map['line_number'] ?? map['lineNumber'] ?? map['line']) as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'page_number': pageNumber,
    'line_number': lineNumber,
  };
}

class BookChapter {
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final int startPage;
  final int startLine;
  final int endPage;
  final int endLine;
  final List<BookSubtitle> subtitles;

  const BookChapter({
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.startPage,
    required this.startLine,
    required this.endPage,
    required this.endLine,
    this.subtitles = const [],
  });

  factory BookChapter.fromMap(Map<String, dynamic> map) {
    List<BookSubtitle> subs = const [];
    final rawSubs = map['subtitles'];
    if (rawSubs is List) {
      subs = rawSubs
          .map((s) => BookSubtitle.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList();
    } else if (rawSubs is String && rawSubs.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSubs);
        if (decoded is List) {
          subs = decoded
              .map((s) => BookSubtitle.fromMap(Map<String, dynamic>.from(s as Map)))
              .toList();
        }
      } catch (_) {}
    }

    return BookChapter(
      bookId: (map['book_id'] ?? map['bookId']) as String? ?? '',
      chapterIndex: ((map['chapter_index'] ?? map['chapterIndex']) as num?)?.toInt() ?? 1,
      chapterTitle: (map['chapter_title'] ?? map['chapterTitle'] ?? map['title']) as String? ?? '',
      startPage: ((map['start_page'] ?? map['startPage']) as num?)?.toInt() ?? 1,
      startLine: ((map['start_line'] ?? map['startLine']) as num?)?.toInt() ?? 1,
      endPage: ((map['end_page'] ?? map['endPage']) as num?)?.toInt() ?? 1,
      endLine: ((map['end_line'] ?? map['endLine']) as num?)?.toInt() ?? 1,
      subtitles: subs,
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
      'subtitles': jsonEncode(subtitles.map((s) => s.toMap()).toList()),
    };
  }
}
