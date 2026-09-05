import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/bible/models/bible_verse_counts.dart';

void main() {
  group('BibleVerseCounts.fromJson', () {
    test('parses a valid array-of-arrays payload', () {
      final counts = BibleVerseCounts.fromJson(const [
        [31, 25, 24],
        [22, 11],
      ]);

      expect(counts.isLoaded, isTrue);
      expect(counts.bookCount, 2);
      expect(counts.chapterCountsForBook(1), [31, 25, 24]);
      expect(counts.chapterCountsForBook(2), [22, 11]);
    });

    test('keeps chapter counts for non-numeric entries as 0', () {
      final counts = BibleVerseCounts.fromJson(const [
        [31, null, 'bad', 25],
      ]);

      expect(counts.chapterCountsForBook(1), [31, 0, 0, 25]);
    });

    test('returns empty for a non-list payload', () {
      final counts = BibleVerseCounts.fromJson('not an array');

      expect(counts.isLoaded, isFalse);
      expect(counts.bookCount, 0);
    });
  });

  group('BibleVerseCounts lookups', () {
    final counts = BibleVerseCounts.fromJson(const [
      [2, 3],
      [5],
      [1, 1, 1],
    ]);

    test('verseRowsInChapter returns the row count for existing chapters', () {
      expect(counts.verseRowsInChapter(bookNumber: 1, chapter: 1), 2);
      expect(counts.verseRowsInChapter(bookNumber: 1, chapter: 2), 3);
      expect(counts.verseRowsInChapter(bookNumber: 2, chapter: 1), 5);
      expect(counts.verseRowsInChapter(bookNumber: 3, chapter: 3), 1);
    });

    test('verseRowsInChapter is 0 for out-of-range books/chapters', () {
      expect(counts.verseRowsInChapter(bookNumber: 0, chapter: 1), 0);
      expect(counts.verseRowsInChapter(bookNumber: 4, chapter: 1), 0);
      expect(counts.verseRowsInChapter(bookNumber: 1, chapter: 3), 0);
      expect(counts.verseRowsInChapter(bookNumber: 3, chapter: 4), 0);
    });

    test('rowsInBook sums across chapters', () {
      expect(counts.rowsInBook(1), 5);
      expect(counts.rowsInBook(2), 5);
      expect(counts.rowsInBook(3), 3);
      expect(counts.rowsInBook(99), 0);
    });
  });
}