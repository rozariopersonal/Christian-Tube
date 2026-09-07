class ArticleLine {
  final int line;
  final String text;
  final bool isHeading;
  final int headingLevel;

  const ArticleLine({
    required this.line,
    required this.text,
    this.isHeading = false,
    this.headingLevel = 1,
  });

  factory ArticleLine.fromJson(Map<String, dynamic> json) {
    return ArticleLine(
      line: json['line'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      isHeading: json['isHeading'] as bool? ?? false,
      headingLevel: json['headingLevel'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'line': line,
        'text': text,
        'isHeading': isHeading,
        'headingLevel': headingLevel,
      };
}

class ArticleData {
  final String id;
  final String title;
  final String date;
  final String author;
  final List<ArticleLine> lines;

  const ArticleData({
    required this.id,
    required this.title,
    required this.date,
    required this.author,
    required this.lines,
  });

  factory ArticleData.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>? ?? [];
    return ArticleData(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled Article',
      date: json['date'] as String? ?? '',
      author: json['author'] as String? ?? 'Zac Poonen',
      lines: rawLines
          .map((l) => ArticleLine.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date,
        'author': author,
        'lines': lines.map((l) => l.toJson()).toList(),
      };
}
