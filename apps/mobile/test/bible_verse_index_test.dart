import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/bible/models/bible_verse_counts.dart';
import 'package:mobile/features/bible/services/bible_verse_index.dart';

// 3-book canon for deterministic math:
//   book 1: [2, 3]   -> rows 0..4
//   book 2: [5]      -> rows 5..9
//   book 3: [1,1,1]  -> rows 10..12
final counts = BibleVerseCounts.fromJson(const [
  [2, 3],
  [5],
  [1, 1, 1],
]);

void main() {
  late BibleVerseIndex index;

  setUp(() {
    index = BibleVerseIndex(counts);
  });

  group('totalVerses & chapter bounds', () {
    test('totalVerses is the sum of all verse rows', () {
      expect(index.totalVerses, 13);
    });

    test('chapterStartRow points at verse 1 of every chapter', () {
      expect(index.chapterStartRow(bookNumber: 1, chapter: 1), 0);
      expect(index.chapterStartRow(bookNumber: 1, chapter: 2), 2);
      expect(index.chapterStartRow(bookNumber: 2, chapter: 1), 5);
      expect(index.chapterStartRow(bookNumber: 3, chapter: 1), 10);
      expect(index.chapterStartRow(bookNumber: 3, chapter: 3), 12);
    });

    test('chapterRowCount matches the model', () {
      expect(index.chapterRowCount(bookNumber: 1, chapter: 1), 2);
      expect(index.chapterRowCount(bookNumber: 2, chapter: 1), 5);
      expect(index.chapterRowCount(bookNumber: 3, chapter: 3), 1);
    });
  });

  group('globalRowFor', () {
    test('maps references to flat rows', () {
      expect(index.globalRowFor(bookNumber: 1, chapter: 1, verse: 1), 0);
      expect(index.globalRowFor(bookNumber: 1, chapter: 1, verse: 2), 1);
      expect(index.globalRowFor(bookNumber: 1, chapter: 2, verse: 3), 4);
      expect(index.globalRowFor(bookNumber: 2, chapter: 1, verse: 1), 5);
      expect(index.globalRowFor(bookNumber: 2, chapter: 1, verse: 5), 9);
      expect(index.globalRowFor(bookNumber: 3, chapter: 3, verse: 1), 12);
    });

    test('round-trips through rowToReference for every row', () {
      for (var row = 0; row < index.totalVerses; row++) {
        final ref = index.rowToReference(row);
        expect(index.globalRowFor(
          bookNumber: ref.bookNumber,
          chapter: ref.chapter,
          verse: ref.verse,
        ), row);
      }
    });
  });

  group('rowToReference', () {
    test('resolves boundary rows', () {
      expect(index.rowToReference(0),
          (bookNumber: 1, chapter: 1, verse: 1));
      expect(index.rowToReference(4),
          (bookNumber: 1, chapter: 2, verse: 3));
      expect(index.rowToReference(5),
          (bookNumber: 2, chapter: 1, verse: 1));
      expect(index.rowToReference(9),
          (bookNumber: 2, chapter: 1, verse: 5));
      expect(index.rowToReference(12),
          (bookNumber: 3, chapter: 3, verse: 1));
    });

    test('clamps negative rows to the first verse', () {
      expect(index.rowToReference(-5),
          (bookNumber: 1, chapter: 1, verse: 1));
    });

    test('clamps past-the-end rows to the last verse', () {
      expect(index.rowToReference(100),
          (bookNumber: 3, chapter: 3, verse: 1));
    });
  });

  group('empty counts', () {
    test('degrades gracefully when no counts are loaded', () {
      final empty = BibleVerseIndex(BibleVerseCounts.fromJson(null));

      expect(empty.totalVerses, 0);
      expect(empty.chapterStartRow(bookNumber: 1, chapter: 1), 0);
      expect(empty.globalRowFor(bookNumber: 1, chapter: 1, verse: 1), 0);
      expect(empty.rowToReference(0),
          (bookNumber: 1, chapter: 1, verse: 1));
    });
  });
}