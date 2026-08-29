class BibleBookmark {
  final String versionId;
  final String book;
  final int chapter;
  final int verse;
  final String text;
  final DateTime savedAt;

  const BibleBookmark({
    required this.versionId,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.savedAt,
  });

  String get reference => '$book $chapter:$verse';

  Map<String, dynamic> toJson() => {
        'versionId': versionId,
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'text': text,
        'savedAt': savedAt.toIso8601String(),
      };

  factory BibleBookmark.fromJson(Map<String, dynamic> json) => BibleBookmark(
        versionId: json['versionId'] as String,
        book: json['book'] as String,
        chapter: json['chapter'] as int,
        verse: json['verse'] as int,
        text: json['text'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
