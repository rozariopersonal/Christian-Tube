import 'package:flutter/foundation.dart';

/// Per-chapter verse-row counts for one Bible version, in canonical order.
///
/// Parses the `bibles/{version}/counts.json` asset published from the releases
/// repo. The file format is a compact array-of-arrays:
///
/// ```
/// [ [31, 25, 24, ...],   // book 1 (Genesis): verse-row count per chapter
///   [22, 11, ...],       // book 2 (Exodus)
///   ... ]                // 66 arrays total
/// ```
///
/// Indexing is canonical-position based (book 1 = Genesis, chapter 1 = first
/// chapter) so the whole file is at most ~66 * 9 * 4 bytes and needs no keys.
///
/// A "verse row" is one entry in a chapter's JSON array (the same unit the
/// reader renders as a scrollable item). In the chunked releases data this
/// always equals the chapter's `verse`-numbered entries because chapter JSON is
/// emitted positionally (`verse: i + 1`).
@immutable
class BibleVerseCounts {
  /// bookIndex (0-based) -> chapterIndex (0-based) -> verse-row count.
  final List<List<int>> _counts;

  const BibleVerseCounts(this._counts);

  /// Parses the counts payload (a JSON array of per-book chapter arrays).
  factory BibleVerseCounts.fromJson(dynamic json) {
    if (json is! List) return const BibleVerseCounts([]);
    final books = <List<int>>[];
    for (final rawBook in json) {
      if (rawBook is! List) continue;
      books.add(
        List.unmodifiable(
          rawBook.map((c) => c is num ? c.toInt() : 0),
        ),
      );
    }
    return BibleVerseCounts(List.unmodifiable(books));
  }

  /// True when at least one book has been parsed.
  bool get isLoaded => _counts.isNotEmpty;

  /// Number of books present (0 when empty, 66 for a full canon).
  int get bookCount => _counts.length;

  /// Verse-row counts for every chapter of [bookNumber] (1-based), or an empty
  /// list when the book is absent from the payload.
  List<int> chapterCountsForBook(int bookNumber) {
    final index = bookNumber - 1;
    if (index < 0 || index >= _counts.length) return const [];
    return _counts[index];
  }

  /// Number of verse rows in a specific chapter, 0 when unknown/out-of-range.
  int verseRowsInChapter({required int bookNumber, required int chapter}) {
    final chapters = chapterCountsForBook(bookNumber);
    final index = chapter - 1;
    if (index < 0 || index >= chapters.length) return 0;
    return chapters[index];
  }

  /// Number of verse rows across every chapter of [bookNumber].
  int rowsInBook(int bookNumber) {
    var sum = 0;
    for (final count in chapterCountsForBook(bookNumber)) {
      sum += count;
    }
    return sum;
  }
}