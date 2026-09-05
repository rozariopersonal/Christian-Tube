import '../../engines/scripture/services/book_name_service.dart';

/// A canonical Bible passage reference (1..66 book number + chapter + optional
/// verse) that any feature can hand to [BiblePassageNavigator] to move the
/// Bible reader to that location.
class BibleReference {
  final int bookNumber;
  final int chapter;
  final int? verse;
  final String? versionId;

  const BibleReference({
    required this.bookNumber,
    required this.chapter,
    this.verse,
    this.versionId,
  });

  /// Builds a reference from a canonical English book name (e.g. "1 Samuel").
  factory BibleReference.fromBookName(
    String bookName,
    int chapter, {
    int? verse,
    String? versionId,
  }) {
    final index = BookNameService.englishBookNames.indexOf(bookName);
    return BibleReference(
      bookNumber: index >= 0 ? index + 1 : 1,
      chapter: chapter,
      verse: verse,
      versionId: versionId,
    );
  }

  /// Canonical English book name for this reference.
  String get bookName => BookNameService.englishNameFor(bookNumber);

  /// Human-readable label like "John 3:16".
  String get label =>
      verse == null ? '$bookName $chapter' : '$bookName $chapter:$verse';
}