class BookScriptureLink {
  final int id;
  final int bookNumber;
  final int chapter;
  final int verse;
  final int endVerse;
  final String bookId;
  final String bookTitle;
  final String author;
  final int pageNumber;
  final int startLine;
  final int endLine;
  final String headline;
  final String excerpt;

  const BookScriptureLink({
    required this.id,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.endVerse,
    required this.bookId,
    required this.bookTitle,
    required this.author,
    required this.pageNumber,
    required this.startLine,
    required this.endLine,
    required this.headline,
    this.excerpt = '',
  });

  BookScriptureLink copyWith({String? excerpt}) {
    return BookScriptureLink(
      id: id,
      bookNumber: bookNumber,
      chapter: chapter,
      verse: verse,
      endVerse: endVerse,
      bookId: bookId,
      bookTitle: bookTitle,
      author: author,
      pageNumber: pageNumber,
      startLine: startLine,
      endLine: endLine,
      headline: headline,
      excerpt: excerpt ?? this.excerpt,
    );
  }

  factory BookScriptureLink.fromMap(Map<String, dynamic> map, {String excerpt = ''}) {
    return BookScriptureLink(
      id: (map['id'] as num?)?.toInt() ?? 0,
      bookNumber: (map['book_number'] as num?)?.toInt() ?? 1,
      chapter: (map['chapter'] as num?)?.toInt() ?? 1,
      verse: (map['verse'] as num?)?.toInt() ?? 1,
      endVerse: (map['end_verse'] as num?)?.toInt() ?? (map['verse'] as num?)?.toInt() ?? 1,
      bookId: map['book_id'] as String? ?? '',
      bookTitle: map['title'] as String? ?? map['book_title'] as String? ?? 'Book',
      author: map['author'] as String? ?? 'Zac Poonen',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      startLine: (map['start_line'] as num?)?.toInt() ?? 1,
      endLine: (map['end_line'] as num?)?.toInt() ?? 1,
      headline: map['headline'] as String? ?? '',
      excerpt: excerpt.isNotEmpty ? excerpt : (map['excerpt'] as String? ?? ''),
    );
  }
}
