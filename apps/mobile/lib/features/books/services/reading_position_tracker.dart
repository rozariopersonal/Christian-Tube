import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_line.dart';

/// The identifier of a rendered reading block, composed of page and start line.
///
/// Encodes the pattern `'$pageNum:$startLine'` used by the reader to track the
/// exact paragraph currently in view, so position can be restored precisely.
class ReadingBlockKey {
  const ReadingBlockKey._();

  /// Builds the canonical key for a block on [pageNum] starting at [startLine].
  static String of(int pageNum, int startLine) => '$pageNum:$startLine';

  /// Parses [key] into `(page, startLine)` or returns null when malformed.
  static (int, int)? parse(String key) {
    final colonIdx = key.indexOf(':');
    if (colonIdx == -1) return null;
    final page = int.tryParse(key.substring(0, colonIdx));
    final line = int.tryParse(key.substring(colonIdx + 1));
    if (page == null || line == null) return null;
    return (page, line);
  }
}

/// Pure, widget-free helpers for tracking a reader's position.
///
/// These methods contain no `BuildContext`/`RenderObject` dependencies, so they
/// are trivially unit-testable. Geometry-driven scanning (finding which block is
/// at a pixel offset) stays in the view layer; this service turns a located
/// block into a page, line, and completion percentage.
class ReadingPositionTracker {
  /// Resolves the chapter whose page range contains [pageNumber], returning its
  /// title, or `''` when no chapter matches.
  static String chapterTitleForPage(List<BookChapter> chapters, int pageNumber) {
    for (final ch in chapters) {
      if (pageNumber >= ch.startPage && pageNumber <= ch.endPage) {
        return ch.chapterTitle;
      }
    }
    return '';
  }

  /// Maps a [startLine] on [pageNumber] into a 0..1 completion fraction using
  /// the book's [totalLines]. Falls back to page-based progress when the line count
  /// is unknown (<= 0).
  static double completionForLine({required double startLine, required int totalLines}) {
    if (totalLines <= 0) return 0.0;
    return (startLine / totalLines).clamp(0.0, 1.0);
  }

  /// Maps a [pageNumber] into a 0..1 completion fraction based on [totalPages].
  static double completionForPage({required double pageNumber, required int totalPages}) {
    if (totalPages <= 0) return 0.0;
    return (pageNumber / totalPages).clamp(0.0, 1.0);
  }

  /// Returns the first line number of [lines], or null when there are none.
  static int? firstLineOf(List<BookLine> lines) {
    if (lines.isEmpty) return null;
    return lines.first.lineNumber;
  }

  /// Locates the [BookChapter] whose page range contains [pageNumber], or null.
  static BookChapter? chapterForPage(List<BookChapter> chapters, int pageNumber) {
    for (final ch in chapters) {
      if (pageNumber >= ch.startPage && pageNumber <= ch.endPage) {
        return ch;
      }
    }
    return null;
  }

  /// Computes completion from the first line of a page's loaded content, or from
  /// the page number itself when no lines are available.
  static double completionForPageLines(
    List<BookLine> lines, {
    required int pageNumber,
    required int totalLines,
    required int totalPages,
  }) {
    final firstLine = firstLineOf(lines);
    if (firstLine != null) {
      return completionForLine(startLine: firstLine.toDouble(), totalLines: totalLines);
    }
    return completionForPage(pageNumber: pageNumber.toDouble(), totalPages: totalPages);
  }

  /// Validates a [Book]'s page count, defaulting to 1.
  static int safeTotalPages(Book? book) {
    final raw = book?.totalPages ?? 1;
    return raw < 1 ? 1 : raw;
  }
}
