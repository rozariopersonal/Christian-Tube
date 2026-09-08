class BibleHighlight {
  final String versionId;
  final String book;
  final int chapter;
  final List<int> verses;
  final int colorIndex;
  final String text;
  final DateTime savedAt;

  const BibleHighlight({
    required this.versionId,
    required this.book,
    required this.chapter,
    required this.verses,
    required this.colorIndex,
    required this.text,
    required this.savedAt,
  });

  String get reference {
    final v = verses;
    if (v.length == 1) return '$book $chapter:${v.first}';
    return '$book $chapter:${v.first}-${v.last}';
  }

  Map<String, dynamic> toJson() => {
        'versionId': versionId,
        'book': book,
        'chapter': chapter,
        'verses': verses,
        'colorIndex': colorIndex,
        'text': text,
        'savedAt': savedAt.toIso8601String(),
      };

  factory BibleHighlight.fromJson(Map<String, dynamic> json) =>
      BibleHighlight(
        versionId: json['versionId'] as String,
        book: json['book'] as String,
        chapter: json['chapter'] as int,
        verses: (json['verses'] as List<dynamic>).cast<int>(),
        colorIndex: json['colorIndex'] as int,
        text: json['text'] as String? ?? '',
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
