import 'book_abbreviation.dart';

/// A single cross-reference targeting another Bible passage.
///
/// Data is translation-independent (from the OpenBible / HelloAO
/// `open-cross-ref` dataset) and is resolved to verse text at display time
/// against the user's currently selected bible version.
class CrossReference {
  /// Canonical book number of the target passage (1-66).
  final int bookNumber;

  final int chapter;

  /// Starting verse of the target passage.
  final int verse;

  /// Ending verse of the target passage; null when it is a single verse.
  final int? endVerse;

  /// OpenBible relevance score (higher = more relevant). Pre-sorted
  /// descending in the dataset.
  final int score;

  const CrossReference({
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    this.endVerse,
    this.score = 0,
  });

  String get bookAbbreviation =>
      BookAbbreviation.abbreviationFor(bookNumber) ??
      bookNumber.toString();

  bool get isRange =>
      endVerse != null && endVerse! > verse;

  /// Readable reference label such as "JHN 1:1-3" or "PSA 23:1".
  String get referenceLabel {
    if (endVerse != null && endVerse! > verse) {
      return '$bookAbbreviation $chapter:$verse-$endVerse';
    }
    return '$bookAbbreviation $chapter:$verse';
  }

  /// Stable cache/identity key for resolved verse text lookups.
  String get textKey => '${bookNumber}_${chapter}_$verse';

  @override
  bool operator ==(Object other) =>
      other is CrossReference &&
      other.bookNumber == bookNumber &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.endVerse == endVerse &&
      other.score == score;

  @override
  int get hashCode => Object.hash(bookNumber, chapter, verse, endVerse, score);

  factory CrossReference.fromJson(Map<String, dynamic> json) =>
      CrossReference(
        bookNumber: (json['b'] as num).toInt(),
        chapter: (json['c'] as num).toInt(),
        verse: (json['v'] as num).toInt(),
        endVerse: json['e'] == null ? null : (json['e'] as num).toInt(),
        score: (json['s'] as num?)?.toInt() ?? 0,
      );
}
