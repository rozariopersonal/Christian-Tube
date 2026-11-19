import 'bible_book.dart';

/// Represents a verse or multi-verse passage returned by Bible search.
class BibleSearchHit {
  final String id;
  final double score;
  final String kind;
  final int? bookNumber;
  final String? bookName;
  final int? chapter;
  final int? verse;
  final int? endVerse;
  final String reference;
  final String text;

  const BibleSearchHit({
    required this.id,
    required this.score,
    this.kind = 'verse',
    this.bookNumber,
    this.bookName,
    this.chapter,
    this.verse,
    this.endVerse,
    required this.reference,
    required this.text,
  });

  bool get isPassage =>
      kind == 'passage' ||
      (endVerse != null && verse != null && endVerse! > verse!);

  String get displayReference {
    if (reference.trim().isNotEmpty) return reference.trim();
    final name = bookName ?? canonicalBookKey ?? 'Bible';
    if (chapter != null && verse != null) {
      if (endVerse != null && endVerse! > verse!) {
        return '$name $chapter:$verse-$endVerse';
      }
      return '$name $chapter:$verse';
    }
    return name;
  }

  /// Resolves the canonical key in [bibleBooks] so navigation succeeds even
  /// when the user is reading a non-English Bible version.
  String? get canonicalBookKey {
    final bn = bookNumber;
    if (bn != null && bn >= 1 && bn <= bibleBooks.length) {
      return bibleBooks.keys.elementAt(bn - 1);
    }
    final name = bookName?.trim();
    if (name != null && bibleBooks.containsKey(name)) {
      return name;
    }
    return null;
  }

  factory BibleSearchHit.fromJson(Map<String, dynamic> json) {
    final bn = _asInt(json['bookNumber']) ?? _asInt(json['book_number']);
    final bookName =
        (json['bookName'] ?? json['book_name']) as String?;
    final chapter = _asInt(json['chapter']);
    final verse = _asInt(json['verse']);
    final endVerse = _asInt(json['endVerse']) ?? _asInt(json['end_verse']);
    final rawKind = json['kind'] as String?;
    final kind = rawKind == 'passage' ||
            (endVerse != null && verse != null && endVerse > verse)
        ? 'passage'
        : 'verse';
    final rawRef = json['reference'] as String?;
    final fallbackRef = (bookName != null && chapter != null && verse != null)
        ? (endVerse != null && endVerse > verse
            ? '$bookName $chapter:$verse-$endVerse'
            : '$bookName $chapter:$verse')
        : '';

    return BibleSearchHit(
      id: (json['id'] ?? '${bn ?? 0}:${chapter ?? 0}:${verse ?? 0}').toString(),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      kind: kind,
      bookNumber: bn,
      bookName: bookName,
      chapter: chapter,
      verse: verse,
      endVerse: endVerse,
      reference: (rawRef != null && rawRef.trim().isNotEmpty)
          ? rawRef.trim()
          : fallbackRef,
      text: (json['text'] as String?) ?? '',
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
