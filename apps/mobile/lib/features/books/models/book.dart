import 'dart:convert';

class Book {
  final String id;
  final String title;
  final String author;
  final String subject;
  final List<String> categories;
  final String description;
  final String coverFile;
  final int totalPages;
  final int totalLines;
  final String downloadSizeFormatted;
  final String createdAt;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    this.subject = 'Christian Living',
    this.categories = const [],
    required this.description,
    required this.coverFile,
    required this.totalPages,
    required this.totalLines,
    this.downloadSizeFormatted = '',
    required this.createdAt,
  });

  factory Book.fromMap(Map<String, dynamic> map) {
    List<String> parsedCategories = [];
    final rawCats = map['categories'];
    if (rawCats is List) {
      parsedCategories = rawCats.map((e) => e.toString()).toList();
    } else if (rawCats is String && rawCats.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCats);
        if (decoded is List) {
          parsedCategories = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return Book(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String? ?? 'Zac Poonen',
      subject: map['subject'] as String? ?? 'Christian Living',
      categories: parsedCategories,
      description: map['description'] as String? ?? '',
      coverFile: (map['cover_file'] ?? map['coverFile'] ?? map['localCoverFile'] ?? '') as String,
      totalPages: ((map['total_pages'] ?? map['totalPages']) as num?)?.toInt() ?? 0,
      totalLines: ((map['total_lines'] ?? map['totalLines']) as num?)?.toInt() ?? 0,
      downloadSizeFormatted: (map['downloadSizeFormatted'] ?? map['download_size_formatted'] ?? '') as String,
      createdAt: (map['created_at'] ?? map['createdAt'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'subject': subject,
      'categories': jsonEncode(categories),
      'description': description,
      'cover_file': coverFile,
      'total_pages': totalPages,
      'total_lines': totalLines,
      'download_size_formatted': downloadSizeFormatted,
      'created_at': createdAt,
    };
  }
}
