import '../models/book_line.dart';
import 'book_service.dart';

/// Streams whole chapters of a single book into memory as the reader scrolls.
///
/// Chapters are fetched on demand through [BookService.getChapterLines] (live
/// GitHub streaming on web, SQLite on device), deduplicated while in flight,
/// and kept once resolved. Chapter resolution also notifies the length probe
/// ([onChapterResolved]) so the owning controller can feed its
/// [BookLineIndex](BookLineIndex) with the discovered chapter boundaries.
///
/// Failed chapters (network/parse errors) resolve to an empty list and are
/// remembered so retries are not hammered during a single session.
class BookChapterStream {
  BookChapterStream(this.bookService, this.bookId, {this.totalChapters});

  final BookService bookService;
  final String bookId;

  /// Canonical chapter count of the book (from its TOC); guards
  /// [preloadAround] from walking past the last chapter. Set once the book's
  /// TOC is known.
  int? totalChapters;

  final Map<int, List<BookLine>> _chapters = {};
  final Map<int, Future<List<BookLine>>> _inFlight = {};
  final Set<int> _failed = {};

  /// Called after a chapter resolves (successfully or with zero lines) so the
  /// controller can extend its line index with the discovered length.
  void Function(int chapterIndex, int lineCount)? onChapterResolved;

  /// True when [chapterIndex] has a resolved (possibly empty) buffer.
  bool contains(int chapterIndex) => _chapters.containsKey(chapterIndex);

  /// Resolved lines for a buffered chapter, or null while not loaded.
  List<BookLine>? bufferedLines(int chapterIndex) => _chapters[chapterIndex];

  /// Whether the chapter previously failed to resolve this session.
  bool hasFailed(int chapterIndex) => _failed.contains(chapterIndex);

  /// Number of chapters currently buffered.
  int get bufferedCount => _chapters.length;

  /// Returns the buffered lines for [chapterIndex], loading them (and
  /// deduplicating concurrent requests) when not already present.
  Future<List<BookLine>> ensureChapter(int chapterIndex) {
    final cached = _chapters[chapterIndex];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[chapterIndex];
    if (pending != null) return pending;
    final future = _loadChapter(chapterIndex);
    _inFlight[chapterIndex] = future;
    return future;
  }

  /// Ensures a ring of buffered chapters around an anchor so continuous
  /// scrolling does not stall at the window edge. Honors the book's chapter
  /// bounds when [totalChapters] is known.
  void preloadAround(int chapterIndex, {int radius = 2}) {
    var ch = chapterIndex.clamp(1, totalChapters ?? chapterIndex).toInt();
    for (var i = 0; i < radius; i++) {
      final next = ch + 1;
      if (totalChapters != null && next > totalChapters!) break;
      ch = next;
      ensureChapter(ch);
    }
    ch = chapterIndex.clamp(1, totalChapters ?? chapterIndex).toInt();
    for (var i = 0; i < radius; i++) {
      final prev = ch - 1;
      if (prev < 1) break;
      ch = prev;
      ensureChapter(ch);
    }
  }

  Future<List<BookLine>> _loadChapter(int chapterIndex) async {
    try {
      final lines = await bookService.getChapterLines(bookId, chapterIndex);
      _chapters[chapterIndex] = lines;
      onChapterResolved?.call(chapterIndex, lines.length);
      return lines;
    } catch (_) {
      _failed.add(chapterIndex);
      _chapters[chapterIndex] = const [];
      onChapterResolved?.call(chapterIndex, 0);
      return const [];
    } finally {
      _inFlight.remove(chapterIndex);
    }
  }

  /// Drops every buffered chapter (used when switching books).
  void clear() {
    _chapters.clear();
    _inFlight.clear();
    _failed.clear();
  }
}