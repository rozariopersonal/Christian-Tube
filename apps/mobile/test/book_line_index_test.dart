import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/books/services/book_line_index.dart';

// Deterministic 4-chapter book:
//   ch1: 5 lines  -> rows  0..4
//   ch2: 3 lines  -> rows  5..7
//   ch3: 10 lines -> rows  8..17
//   ch4: 2 lines  -> rows 18..19
const totalLines = 20;

void main() {
  group('empty index', () {
    test('degrades gracefully with no chapters probed', () {
      final index = BookLineIndex(totalLines: totalLines);

      expect(index.chapterCount, 0);
      expect(index.knownRowCount, 0);
      expect(index.isComplete, isFalse);
      expect(index.chapterForRow(0), isNull);
      expect(index.splitRow(0), isNull);
      expect(index.lengthOf(1), isNull);
      expect(index.exactStartRow(1), 0);
    });
  });

  group('incremental discovery', () {
    test('builds offsets from chapters probed out of order', () {
      final index = BookLineIndex(totalLines: totalLines);

      index.extend(3, 10);
      index.extend(1, 5);
      index.extend(2, 3);
      index.extend(4, 2);

      expect(index.chapterCount, 4);
      expect(index.knownRowCount, 20);
      expect(index.isComplete, isTrue);

      expect(index.startRow(1), 0);
      expect(index.startRow(2), 5);
      expect(index.startRow(3), 8);
      expect(index.startRow(4), 18);
      expect(index.exactStartRow(3), 8);
      expect(index.exactStartRow(4), 18);

      expect(index.lengthOf(1), 5);
      expect(index.lengthOf(4), 2);
    });

    test('extend is idempotent and tolerant of non-positive counts', () {
      final index = BookLineIndex(totalLines: totalLines);

      index.extend(1, 5);
      index.extend(1, 5);
      expect(index.lengthOf(1), 5);

      index.extend(2, 0);
      expect(index.lengthOf(2), 0);
      expect(index.startRow(3), 5);

      index.extend(3, -4);
      expect(index.lengthOf(3), 0);
    });
  });

  group('chapterForRow', () {
    test('maps every boundary row to its chapter', () {
      final index = _fullyIndexed();

      final expected = <int, int>{
        for (var r = 0; r <= 4; r++) r: 1,
        for (var r = 5; r <= 7; r++) r: 2,
        for (var r = 8; r <= 17; r++) r: 3,
        for (var r = 18; r <= 19; r++) r: 4,
      };
      expected.forEach((row, chapter) {
        expect(index.chapterForRow(row), chapter, reason: 'row $row');
      });
    });

    test('clamps out-of-range rows', () {
      final index = _fullyIndexed();

      expect(index.chapterForRow(-5), 1);
      expect(index.chapterForRow(100), 4);
    });

    test('resolves to best-known chapter in an undiscovered gap', () {
      final index = BookLineIndex(totalLines: totalLines);
      index.extend(1, 5);
      index.extend(3, 10);

      expect(index.chapterForRow(2), 1);
      expect(index.chapterForRow(6), 3);
      expect(index.chapterForRow(14), 3);
    });
  });

  group('splitRow', () {
    test('round-trips every row of a fully-contiguous book', () {
      final index = _fullyIndexed();

      final expected = <int, ({int chapterIndex, int ordinal})>{
        for (var r = 0; r <= 4; r++) r: (chapterIndex: 1, ordinal: r),
        for (var r = 5; r <= 7; r++) r: (chapterIndex: 2, ordinal: r - 5),
        for (var r = 8; r <= 17; r++) r: (chapterIndex: 3, ordinal: r - 8),
        for (var r = 18; r <= 19; r++) r: (chapterIndex: 4, ordinal: r - 18),
      };
      expected.forEach((row, want) {
        expect(index.splitRow(row), want, reason: 'row $row');
      });
    });

    test('returns null for gap and prefix-incomplete rows', () {
      final index = BookLineIndex(totalLines: totalLines);
      index.extend(1, 5);
      index.extend(3, 10);

      expect(index.splitRow(2), (chapterIndex: 1, ordinal: 2));
      expect(index.splitRow(6), isNull, reason: 'row in undiscovered ch2');
      expect(index.splitRow(14), isNull, reason: 'ch3 prefix incomplete');
    });

    test('becomes resolvable once the gap is closed', () {
      final index = BookLineIndex(totalLines: totalLines);
      index.extend(1, 5);
      index.extend(3, 10);

      index.extend(2, 3);

      expect(index.splitRow(6), (chapterIndex: 2, ordinal: 1));
      expect(index.splitRow(14), (chapterIndex: 3, ordinal: 6));
    });
  });

  group('totalLines cap', () {
    test('knownRowCount never exceeds totalLines', () {
      final index = BookLineIndex(totalLines: 18);
      index.extend(1, 5);
      index.extend(2, 3);
      index.extend(3, 10);
      index.extend(4, 2);

      expect(index.knownRowCount, 18);
      expect(index.isComplete, isTrue);
      expect(index.chapterForRow(17), 3);
    });
  });
}

BookLineIndex _fullyIndexed() {
  final index = BookLineIndex(totalLines: totalLines);
  index.extend(1, 5);
  index.extend(2, 3);
  index.extend(3, 10);
  index.extend(4, 2);
  return index;
}