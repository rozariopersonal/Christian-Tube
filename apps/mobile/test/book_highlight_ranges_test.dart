import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/services/book_highlight_ranges.dart';
import 'package:mobile/features/books/widgets/formatted_paragraph.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

void main() {
  const lines = [
    BookLine(
        bookId: 'b',
        pageNumber: 1,
        lineNumber: 1,
        chapterIndex: 1,
        text: 'Grace'),
    BookLine(
        bookId: 'b',
        pageNumber: 1,
        lineNumber: 2,
        chapterIndex: 1,
        text: 'Grace John 3:16'),
  ];
  const highlight = BookHighlight(
      id: 'book_range_2_1',
      bookId: 'b',
      chapterIndex: 1,
      pageNumber: 1,
      startChar: 0,
      endChar: 5,
      text: 'Grace',
      color: 0,
      createdAt: '');
  test('projects the selected source line across both layouts', () {
    final grouped = BookHighlightRanges.project(
        'Grace Grace John 3:16', lines, [highlight]);
    expect(grouped.single.start, 6);
    expect(grouped.single.end, 11);
    final single =
        BookHighlightRanges.project('Grace John 3:16', [lines[1]], [highlight]);
    expect(single.single.start, 0);
    expect(
        BookHighlightRanges.project('Grace', [lines[0]], [highlight]), isEmpty);
  });
  test('renders only the selected duplicate and can span scripture tokens', () {
    const referenceHighlight = BookHighlight(
        id: 'book_range_2_2',
        bookId: 'b',
        chapterIndex: 1,
        pageNumber: 1,
        startChar: 0,
        endChar: 15,
        text: 'Grace John 3:16',
        color: 0,
        createdAt: '');
    final spans = FormattedParagraphBuilder.build(
        'Grace Grace John 3:16',
        const Color(0xff000000),
        AppTokens.light,
        ReaderAppearance(),
        [referenceHighlight],
        sourceLines: lines,
        makeRecognizer: (_, __) => TapGestureRecognizer()).cast<TextSpan>();
    final tinted = spans
        .where((s) => s.style?.backgroundColor != null)
        .map((s) => s.text)
        .join();
    expect(tinted, 'Grace John 3:16');
    expect(spans.first.style?.backgroundColor, isNull);
  });
}
