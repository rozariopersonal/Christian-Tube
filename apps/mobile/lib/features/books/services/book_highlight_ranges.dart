import '../models/book_highlight.dart';
import '../models/book_line.dart';

/// Maps source line positions to offsets in the text shown in either book layout.
class BookHighlightRanges {
  static final _idPattern = RegExp(r'^book_range_(\d+)_');

  static int? lineNumber(BookHighlight highlight) =>
      int.tryParse(_idPattern.firstMatch(highlight.id)?.group(1) ?? '');

  static Iterable<({BookLine line, int start, int end})> lineSpans(
      String text, Iterable<BookLine> lines) sync* {
    var cursor = 0;
    for (final line in lines) {
      final value = line.text.trim();
      if (value.isEmpty || line.contentType == 'img') continue;
      final start = text.indexOf(value, cursor);
      if (start < 0) continue;
      final end = start + value.length;
      yield (line: line, start: start, end: end);
      cursor = end;
    }
  }

  static List<({int start, int end, BookHighlight highlight})> project(
      String text,
      Iterable<BookLine> lines,
      Iterable<BookHighlight> highlights) {
    final spans = lineSpans(text, lines).toList();
    final result = <({int start, int end, BookHighlight highlight})>[];
    for (final highlight in highlights) {
      final line = lineNumber(highlight);
      if (line == null) continue;
      for (final span in spans) {
        if (span.line.lineNumber != line) continue;
        final start = span.start + highlight.startChar;
        final end = span.start + highlight.endChar;
        if (start >= span.start &&
            end <= span.end &&
            start < end &&
            text.substring(start, end) == highlight.text) {
          result.add((start: start, end: end, highlight: highlight));
        }
      }
    }
    return result;
  }
}
