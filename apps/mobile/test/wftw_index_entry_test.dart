import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';

WftwIndexEntry entry(
  String id,
  String title,
  String date,
  {int? year,
  int? bookNumber,
  int? chapter,
  int? startVerse,
  int? endVerse}) {
  return WftwIndexEntry(
    id: id,
    title: title,
    date: date,
    year: year,
    bookNumber: bookNumber,
    chapter: chapter,
    startVerse: startVerse,
    endVerse: endVerse,
  );
}

void main() {
  group('WftwIndexEntry.fromJson', () {
    test('parses a full entry', () {
      final e = WftwIndexEntry.fromJson({
        'id': '2026_09_06',
        'title': 'Few Will Find the Narrow Way',
        'date': '2026-09-06',
        'year': 2026,
        'bookNumber': 40,
        'chapter': 7,
        'startVerse': 13,
        'endVerse': 14,
      });
      expect(e.id, '2026_09_06');
      expect(e.year, 2026);
      expect(e.hasPrimaryVerse, isTrue);
    });

    test('defaults nulls for verse-less entries', () {
      final e = WftwIndexEntry.fromJson({
        'id': '2001_01_07',
        'title': 'Three Marks Of A Spiritual Man',
        'date': '2001-01-07',
        'year': 2001,
      });
      expect(e.bookNumber, isNull);
      expect(e.hasPrimaryVerse, isFalse);
    });
  });

  group('groupByYear', () {
    test('groups by year descending, entries newest-first, drops null years',
        () {
      final grouped = groupByYear([
        entry('a', 'A', '2026-09-06', year: 2026),
        entry('b', 'B', '2001-01-07', year: 2001),
        entry('c', 'C', '2026-01-01', year: 2026),
        entry('d', 'D', 'bad-date', year: null),
      ]);
      expect(grouped.keys.toList(), [2026, 2001]);
      expect(grouped[2026]!.map((e) => e.id).toList(), ['a', 'c']);
      expect(grouped.length, 2);
    });
  });

  group('formatWftwDate', () {
    test('formats ISO date to friendly label', () {
      expect(formatWftwDate('2026-09-06'), 'Sep 6, 2026');
      expect(formatWftwDate('2001-01-07'), 'Jan 7, 2001');
    });

    test('passes through unexpected input', () {
      expect(formatWftwDate(''), '');
      expect(formatWftwDate('nonsense'), 'nonsense');
    });
  });
}