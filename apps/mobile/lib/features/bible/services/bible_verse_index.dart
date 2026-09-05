import '../models/bible_verse_counts.dart';

/// Maps a Bible reference to a flat, zero-based "global row" across the
/// entire canon, and back.
///
/// A global row corresponds to the rendered position of one verse item in a
/// continuous whole-Bible reader list. Because the list materializes verses
/// from chapter JSON in canonical order, the row for
/// `(bookNumber, chapter, verse)` is the number of verse rows in every earlier
/// chapter plus `verse - 1`.
///
/// The mapping is built from per-chapter row counts ([BibleVerseCounts]) and
/// defines the contract the scroll layer uses:
///
/// * a word-feed / route jump to (book, chapter, verse) becomes a
///   `scrollTo(index: globalRowFor(...))` against the reader's
///   `ItemScrollController`;
/// * visible-item streams resolve back to a reference via [rowToReference]
///   so the UI can track which chapter is at the top and persist "last read";
/// * prefetch decisions use [chapterStartRow] / [chapterRowCount] to know how
///   far the currently loaded window extends.
///
/// Out-of-range lookups are tolerated: unknown chapters count as 0 rows, and
/// [rowToReference] clamps to the first/last known verse. This keeps the index
/// usable while counts for a chapter are still being streamed.
class BibleVerseIndex {
  BibleVerseIndex(this.counts);

  final BibleVerseCounts counts;

  /// Prefix sums of rows before each book; index `bookNumber - 1`.
  late final List<int> _bookPrefixSum = _buildBookPrefix();

  List<int> _buildBookPrefix() {
    final prefix = <int>[0];
    var sum = 0;
    final bookCount = counts.bookCount.clamp(0, 66);
    for (var bookNumber = 1; bookNumber <= bookCount; bookNumber++) {
      sum += counts.rowsInBook(bookNumber);
      prefix.add(sum);
    }
    return List.unmodifiable(prefix);
  }

  /// Total verse rows known about, across all 66 canonical books.
  int get totalVerses =>
      _bookPrefixSum.isEmpty ? 0 : _bookPrefixSum.last;

  /// First global row belonging to a chapter (the row of its verse 1).
  int chapterStartRow({required int bookNumber, required int chapter}) {
    if (bookNumber < 1 || bookNumber >= _bookPrefixSum.length) return 0;
    var start = _bookPrefixSum[bookNumber - 1];
    final chapters = counts.chapterCountsForBook(bookNumber);
    for (var c = 1; c < chapter && c <= chapters.length; c++) {
      start += chapters[c - 1];
    }
    return start;
  }

  /// Number of verse rows in a chapter.
  int chapterRowCount({required int bookNumber, required int chapter}) =>
      counts.verseRowsInChapter(bookNumber: bookNumber, chapter: chapter);

  /// Flat, zero-based row for a verse. Verse numbering is assumed contiguous
  /// from 1 per chapter (`verse - 1` rows inside the chapter), matching the
  /// chunked releases format. The result is not clamped; callers that need a
  /// valid row should verify the reference first.
  int globalRowFor({
    required int bookNumber,
    required int chapter,
    required int verse,
  }) =>
      chapterStartRow(bookNumber: bookNumber, chapter: chapter) + (verse - 1);

  /// Returns the reference at [globalRow] (0-based). Negative rows resolve to
  /// the first verse; rows beyond the last known verse clamp to the last.
  ({int bookNumber, int chapter, int verse}) rowToReference(int globalRow) {
    final total = totalVerses;
    var remaining = globalRow < 0
        ? 0
        : (total > 0 && globalRow >= total ? total - 1 : globalRow);

    for (var bookNumber = 1;
        bookNumber <= counts.bookCount && remaining >= 0;
        bookNumber++) {
      final bookRows = counts.rowsInBook(bookNumber);
      if (remaining < bookRows) {
        final chapters = counts.chapterCountsForBook(bookNumber);
        for (var chapter = 1; chapter <= chapters.length; chapter++) {
          final chapterRows = chapters[chapter - 1];
          if (remaining < chapterRows) {
            return (
              bookNumber: bookNumber,
              chapter: chapter,
              verse: remaining + 1,
            );
          }
          remaining -= chapterRows;
        }
        break;
      }
      remaining -= bookRows;
    }
    return (bookNumber: 1, chapter: 1, verse: 1);
  }
}