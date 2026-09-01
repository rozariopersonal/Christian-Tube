class Book {
  final String id;
  final String title;
  final String author;
  final String description;
  final String coverFile;
  final int totalPages;
  final int totalLines;
  final String createdAt;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.coverFile,
    required this.totalPages,
    required this.totalLines,
    required this.createdAt,
  });

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String? ?? 'Zac Poonen',
      description: map['description'] as String? ?? '',
      coverFile: map['cover_file'] as String? ?? '',
      totalPages: (map['total_pages'] as num?)?.toInt() ?? 0,
      totalLines: (map['total_lines'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'cover_file': coverFile,
      'total_pages': totalPages,
      'total_lines': totalLines,
      'created_at': createdAt,
    };
  }
}
