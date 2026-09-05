import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../models/bible_book.dart';
import '../models/bible_verse.dart';

/// Canonical composite key for a `(bookNumber, chapter)` pair. Used as the map
/// key wherever the reader buffers whole chapters.
int bibleChapterId(int bookNumber, int chapter) => bookNumber * 1000 + chapter;

/// Maps raw adapter rows (plain maps) to reader rows ([BibleVerse]).
///
/// Rows are ordered by verse number; the reader renders them positionally,
/// which is why the global-row index may assume `verse N` sits at `N - 1`.
List<BibleVerse> chapterVersesFromRows(
  List<Map<String, dynamic>> rows,
  String versionId,
) {
  final byNumber = <int, String>{
    for (final m in rows)
      if (m['verse'] is num && m['text'] is String)
        (m['verse'] as num).toInt(): m['text'] as String,
  };
  final numbers = byNumber.keys.toList()..sort();
  final verses = <BibleVerse>[];
  for (final n in numbers) {
    final text = byNumber[n];
    if (text == null) continue;
    verses.add(BibleVerse(
      number: n,
      text: text,
      versionLabel: versionId,
    ));
  }
  return verses;
}

/// Streams whole chapters of a single Bible version into memory as the reader
/// scrolls.
///
/// Chapters are fetched on demand through [LocalBibleService] (live GitHub
/// streaming on web, SQLite on device), deduplicated while in flight, kept once
/// resolved, and dropped from the buffer when [clear] is called (e.g. version
/// switch). Failed chapters resolve to an empty list and are remembered so
/// retries are not hammered during a single session.
class BibleChapterStream {
  BibleChapterStream(this.versionId, {this.onChapterLoaded});

  final String versionId;
  final void Function(int bookNumber, int chapter, List<BibleVerse> verses)?
      onChapterLoaded;
  final LocalBibleService _service = LocalBibleService();
  final Map<int, List<BibleVerse>> _chapters = {};
  final Map<int, Future<List<BibleVerse>>> _inFlight = {};
  final Set<int> _failed = {};

  /// True when [bookNumber]/[chapter] has a resolved (possibly empty) buffer.
  bool contains(int bookNumber, int chapter) =>
      _chapters.containsKey(bibleChapterId(bookNumber, chapter));

  /// Whether the chapter previously failed to resolve this session.
  bool hasFailed(int bookNumber, int chapter) =>
      _failed.contains(bibleChapterId(bookNumber, chapter));

  /// Returns the buffered rows for [bookNumber]/[chapter], loading them (and
  /// deduplicating concurrent requests) when not already present.
  Future<List<BibleVerse>> ensureChapter(int bookNumber, int chapter) {
    final id = bibleChapterId(bookNumber, chapter);
    final cached = _chapters[id];
    if (cached != null) {
      onChapterLoaded?.call(bookNumber, chapter, cached);
      return Future.value(cached);
    }
    final pending = _inFlight[id];
    if (pending != null) return pending;
    final future = _loadChapter(bookNumber, chapter);
    _inFlight[id] = future;
    return future;
  }

  /// Ensures a ring of buffered chapters around an anchor so continuous
  /// scrolling does not stall at the window edge.
  void preloadAround(int bookNumber, int chapter, {int radius = 2}) {
    var book = bookNumber;
    var ch = chapter;
    for (var i = 0; i < radius; i++) {
      final next = nextChapter(book, ch);
      if (next == null) break;
      book = next.$1;
      ch = next.$2;
      ensureChapter(book, ch);
    }
    book = bookNumber;
    ch = chapter;
    for (var i = 0; i < radius; i++) {
      final prev = prevChapter(book, ch);
      if (prev == null) break;
      book = prev.$1;
      ch = prev.$2;
      ensureChapter(book, ch);
    }
  }

  Future<List<BibleVerse>> _loadChapter(int bookNumber, int chapter) async {
    final id = bibleChapterId(bookNumber, chapter);
    try {
      final bookName = BookNameService.englishBookNames[bookNumber - 1];
      final rows = await _service.getChapter(versionId, bookName, chapter);
      final verses = chapterVersesFromRows(rows, versionId);
      _chapters[id] = verses;
      onChapterLoaded?.call(bookNumber, chapter, verses);
      return verses;
    } catch (_) {
      _failed.add(id);
      _chapters[id] = const [];
      onChapterLoaded?.call(bookNumber, chapter, const []);
      return const [];
    } finally {
      _inFlight.remove(id);
    }
  }

  (int, int)? nextChapter(int bookNumber, int chapter) {
    final books = bibleBooks.keys.toList();
    var maxChapters = bibleBooks[books[bookNumber - 1]] ?? 1;
    var nextBook = bookNumber;
    var nextChapter = chapter + 1;
    if (nextChapter > maxChapters) {
      if (nextBook >= books.length) return null;
      nextBook += 1;
      nextChapter = 1;
    }
    return (nextBook, nextChapter);
  }

  (int, int)? prevChapter(int bookNumber, int chapter) {
    final books = bibleBooks.keys.toList();
    var prevBook = bookNumber;
    var prevChapter = chapter - 1;
    if (prevChapter < 1) {
      if (prevBook <= 1) return null;
      prevBook -= 1;
      prevChapter = bibleBooks[books[prevBook - 1]] ?? 1;
    }
    return (prevBook, prevChapter);
  }

  /// Drops every buffered chapter (used when switching versions).
  void clear() {
    _chapters.clear();
    _inFlight.clear();
    _failed.clear();
  }
}