class UserReadingProgress {
  final String bookId;
  final int currentPage;
  final int currentLine;
  final double completionPercent;
  final String lastReadAt;

  const UserReadingProgress({
    required this.bookId,
    required this.currentPage,
    required this.currentLine,
    required this.completionPercent,
    required this.lastReadAt,
  });

  factory UserReadingProgress.fromMap(Map<String, dynamic> map) {
    return UserReadingProgress(
      bookId: map['book_id'] as String? ?? '',
      currentPage: (map['current_page'] as num?)?.toInt() ?? 1,
      currentLine: (map['current_line'] as num?)?.toInt() ?? 1,
      completionPercent: (map['completion_percent'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: map['last_read_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'book_id': bookId,
      'current_page': currentPage,
      'current_line': currentLine,
      'completion_percent': completionPercent,
      'last_read_at': lastReadAt,
    };
  }
}
