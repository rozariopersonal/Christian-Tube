import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_card.dart';
import 'package:mobile/features/micro_feed/engines/wftw/models/wftw_filter_state.dart';

void main() {
  group('WftwCard.fromMap', () {
    test('maps a verse-backed row into a card with reference label', () {
      final card = WftwCard.fromMap({
        'article_id': '2024_10_26',
        'date_ms': DateTime.utc(2024, 10, 26).millisecondsSinceEpoch,
        'year': 2024,
        'book_number': 40,
        'chapter': 5,
        'start_verse': 3,
        'end_verse': 4,
        'article_title': 'Faith in Trials',
        'fallback_excerpt': null,
      });

      expect(card.articleId, '2024_10_26');
      expect(card.articleTitle, 'Faith in Trials');
      expect(card.year, 2024);
      expect(card.hasPrimaryVerse, isTrue);
      expect(card.referenceLabel, 'Matthew 5:3-4');
      expect(card.formattedDate, 'Oct 26, 2024');
    });

    test('single verse drops the range from the reference label', () {
      final card = WftwCard.fromMap({
        'article_id': 'a',
        'date_ms': 0,
        'book_number': 1,
        'chapter': 1,
        'start_verse': 1,
        'end_verse': 1,
        'article_title': 't',
      });

      expect(card.referenceLabel, 'Genesis 1:1');
    });

    test('row without verses falls back to the excerpt and is not tappable', () {
      final card = WftwCard.fromMap({
        'article_id': '2024_11_02',
        'date_ms': DateTime.utc(2024, 11, 2).millisecondsSinceEpoch,
        'year': 2024,
        'book_number': null,
        'chapter': null,
        'start_verse': null,
        'end_verse': null,
        'article_title': 'Titles Matter',
        'fallback_excerpt': 'Sometimes a leader speaks plainly...',
      });

      expect(card.hasPrimaryVerse, isFalse);
      expect(card.referenceLabel, isEmpty);
      expect(card.fallbackExcerpt, 'Sometimes a leader speaks plainly...');
      expect(card.resolvedText, 'Sometimes a leader speaks plainly...');
    });

    test('defaults article title when the row omits one', () {
      final card = WftwCard.fromMap({
        'article_id': 'a',
        'date_ms': 0,
        'article_title': null,
      });
      expect(card.articleTitle, 'Word for the Week');
    });
  });

  group('WftwFilterState', () {
    test('copyWith updates a single field and preserves the rest', () {
      const base = WftwFilterState();
      final changed = base.copyWith(sortBy: 'book');
      expect(changed.sortBy, 'book');
      expect(changed.activeVersionId, base.activeVersionId);
      expect(changed.yearFilter, isNull);
    });

    test('copyWith clearYearFilter removes the filter', () {
      final withFilter =
          const WftwFilterState().copyWith(yearFilter: 2024);
      expect(withFilter.yearFilter, 2024);
      final cleared = withFilter.copyWith(clearYearFilter: true);
      expect(cleared.yearFilter, isNull);
    });

    test('copyWith clearBookFilter removes the filter', () {
      final withFilter =
          const WftwFilterState().copyWith(bookFilter: 40);
      expect(withFilter.bookFilter, 40);
      final cleared = withFilter.copyWith(clearBookFilter: true);
      expect(cleared.bookFilter, isNull);
    });
  });
}