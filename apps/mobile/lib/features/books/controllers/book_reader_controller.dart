import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import '../../../shared/services/reader_appearance.dart';
import '../services/book_chapter_stream.dart';
import '../services/book_line_index.dart';
import '../services/book_service.dart';
import '../services/page_loader.dart';
import '../services/reading_position_tracker.dart';

/// Immutable snapshot of the reader's visible behavioral state.
///
/// The view reads these fields (never raw controller internals) so widget tests
/// can drive a fake/recorded controller deterministically.
class BookReaderState {
  final bool isLoading;
  final Book? book;
  final List<BookChapter> chapters;
  final int currentPage;
  final int spreadLeftPage;
  final bool showChrome;

  final int lastReadPage;
  final int lastReadLine;
  final double lastPercent;

  // Page-mode (non-continuous) buffer orientation relative to the center page.
  // Unused by the continuous reader, which derives position purely from rows.
  final int centerPage;
  final List<int> prevPages;
  final List<int> nextPages;

  /// Continuous whole-book scroll mode (see [BookLineIndex]).
  final bool useContinuous;

  /// Global row to restore after load in continuous mode.
  final int resumeRow;

  const BookReaderState({
    required this.isLoading,
    required this.book,
    required this.chapters,
    required this.currentPage,
    required this.spreadLeftPage,
    required this.showChrome,
    required this.lastReadPage,
    required this.lastReadLine,
    required this.lastPercent,
    required this.centerPage,
    required this.prevPages,
    required this.nextPages,
    this.useContinuous = false,
    this.resumeRow = 0,
  });

  BookReaderState copyWith({
    bool? isLoading,
    Book? book,
    List<BookChapter>? chapters,
    int? currentPage,
    int? spreadLeftPage,
    bool? showChrome,
    int? lastReadPage,
    int? lastReadLine,
    double? lastPercent,
    int? centerPage,
    List<int>? prevPages,
    List<int>? nextPages,
    bool? useContinuous,
    int? resumeRow,
  }) {
    return BookReaderState(
      isLoading: isLoading ?? this.isLoading,
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
      currentPage: currentPage ?? this.currentPage,
      spreadLeftPage: spreadLeftPage ?? this.spreadLeftPage,
      showChrome: showChrome ?? this.showChrome,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      lastReadLine: lastReadLine ?? this.lastReadLine,
      lastPercent: lastPercent ?? this.lastPercent,
      centerPage: centerPage ?? this.centerPage,
      prevPages: prevPages ?? this.prevPages,
      nextPages: nextPages ?? this.nextPages,
      useContinuous: useContinuous ?? this.useContinuous,
      resumeRow: resumeRow ?? this.resumeRow,
    );
  }
}

/// Owns the reader's behavioral state and data loading.
///
/// This controller holds:
/// - the currently loaded [Book] and its chapters
/// - the current reading position (page/line/percent)
/// - the infinite-scroll + dual-page-spread index state
/// - chrome (app bar / nav bar) visibility
///
/// It delegates page loading to [PageLoader] and appearance to
/// [ReaderAppearance], and persists reading progress to [BookService].
///
/// Geometry (GlobalKeys, ScrollController `ensureVisible`, tap recognizers) is
/// *not* owned here — that stays in the view layer, which coordinates it with
/// this controller's state transitions.
class BookReaderController extends ChangeNotifier {
  final BookService _bookService;
  final String _bookId;
  final int? _requestedStartLine;

  /// Page loading / caching, independent of widget lifecycle.
  final PageLoader pageLoader;

  /// Reading appearance (theme, fonts), persisted to SharedPreferences.
  final ReaderAppearance appearance;

  /// Continuous whole-book scroll stream (see [BookChapterStream]); created
  /// regardless of mode so the wiring never swaps instance identity.
  final BookChapterStream continuousStream;

  /// Whether this controller drives the continuous scroll reader.
  final bool useContinuous;

  BookLineIndex? _lineIndex;

  BookReaderState _state = const BookReaderState(
    isLoading: true,
    book: null,
    chapters: [],
    currentPage: 1,
    spreadLeftPage: 1,
    showChrome: true,
    lastReadPage: 1,
    lastReadLine: 1,
    lastPercent: 0.0,
    centerPage: 1,
    prevPages: [],
    nextPages: [],
  );

  BookReaderState get state => _state;

  /// Global-row index for continuous mode; null while not loaded.
  BookLineIndex? get lineIndex => _lineIndex;

  bool _hasUnsavedProgress = false;
  Timer? _idleTimer;
  int? _pendingResumeLine;
  Timer? _backfillTimer;
  bool _backfillRunning = false;
  bool _disposed = false;

  /// Idle delay before the continuous reader back-fills every remaining
  /// chapter into memory. While the reader sits still this fills sequential
  /// gaps so a later jump or fast fling never stalls on a cold chapter.
  static const Duration _backfillIdleDelay = Duration(seconds: 10);

  BookReaderController(
    this._bookService,
    this._bookId, {
    int? initialPage,
    int? highlightStartLine,
    this.useContinuous = false,
  })  : _requestedStartLine = highlightStartLine,
        pageLoader = PageLoader(_bookService, _bookId),
        appearance = ReaderAppearance(),
        continuousStream = BookChapterStream(_bookService, _bookId) {
    appearance.addListener(notifyListeners);
    continuousStream.onChapterResolved = _onContinuousChapterResolved;
    final startPage = (initialPage ?? 1).clamp(1, 999999999);
    _state = _state.copyWith(
      currentPage: startPage,
      centerPage: startPage,
      spreadLeftPage: startPage,
      nextPages: <int>[startPage],
      useContinuous: useContinuous,
    );
    if (highlightStartLine != null) {
      _state = _state.copyWith(lastReadLine: highlightStartLine);
    }
  }

  /// Whether we still owe the user a scroll to the resume position.
  bool get hasPendingResume => _pendingResumeLine != null;
  int? get pendingResumePage => _state.currentPage;

  bool get hasUnsavedProgress => _hasUnsavedProgress;
  int get lastReadPage => _state.lastReadPage;
  int get lastReadLine => _state.lastReadLine;
  double get lastPercent => _state.lastPercent;

  Future<void> load() async {
    final book = await _bookService.getBook(_bookId);
    if (_disposed) return;
    if (book == null) {
      _set(_state.copyWith(isLoading: false));
      return;
    }

    final chapters = await _bookService.getChapters(_bookId);
    if (_disposed) return;

    // Resolve initial position: explicit target wins, else restore saved progress.
    var initialPage = _state.currentPage;
    var initialLine = _requestedStartLine ?? 1;
    var lastPercent = _state.lastPercent;

    final wantsResume = initialPage == 1 && _requestedStartLine == null;
    if (wantsResume) {
      final saved = await _bookService.getProgress(_bookId);
      if (saved != null) {
        initialPage = saved.currentPage.clamp(1, book.totalPages);
        initialLine = saved.currentLine;
        lastPercent = saved.completionPercent;
      }
    }

    if (lastPercent == 0.0 && book.totalPages > 0) {
      lastPercent = (initialPage / book.totalPages).clamp(0.0, 1.0);
    }

    if (useContinuous) {
      _lineIndex = BookLineIndex(totalLines: book.totalLines);
      continuousStream.totalChapters =
          chapters.isEmpty ? null : chapters.length;
      final resumeRow = await _resolveRow(chapters, initialPage, initialLine);
      if (_disposed) return;
      _pendingResumeLine = initialLine;
      _set(_state.copyWith(
        book: book,
        chapters: chapters,
        isLoading: false,
        currentPage: initialPage,
        spreadLeftPage: initialPage,
        lastReadPage: initialPage,
        lastReadLine: initialLine,
        lastPercent: lastPercent,
        resumeRow: resumeRow,
      ));
      _scheduleBackfill();
      return;
    }

    final spreadLeft = PageLoader.spreadLeftForPage(initialPage, book.totalPages);

    final (prev, next) = _adjacentBuffers(initialPage, book.totalPages);

    _pendingResumeLine = wantsResume ? initialLine : _requestedStartLine;
    pageLoader.pendingResumePage = initialPage;
    pageLoader.pendingResumeLine = _pendingResumeLine;

    _set(_state.copyWith(
      book: book,
      chapters: chapters,
      isLoading: false,
      currentPage: initialPage,
      spreadLeftPage: spreadLeft,
      centerPage: initialPage,
      lastReadPage: initialPage,
      lastReadLine: initialLine,
      lastPercent: lastPercent,
      prevPages: prev,
      nextPages: next,
    ));

    await pageLoader.preloadAdjacentPages(
      initialPage,
      book,
      isDualPage: false,
    );
  }

  /// Marks the resume as delivered once the view has scrolled to it.
  void clearPendingResume() {
    _pendingResumeLine = null;
    pageLoader.pendingResumeLine = null;
    pageLoader.pendingResumePage = null;
  }

  /// Records a position change: updates last-read page/line/percent and arms the
  /// 5-minute idle save timer.
  void markProgress(int page, int line, double percent) {
    final pct = percent.clamp(0.0, 1.0);
    _set(_state.copyWith(
      currentPage: page,
      lastReadPage: page,
      lastReadLine: line,
      lastPercent: pct,
    ));
    _armProgressIdleSave();
  }

  /// Records continuous-mode progress from the leading visible global [row].
  /// Derives page/line from the buffered source line so existing page-based
  /// consumers (catalog "continue", reader chrome) keep working.
  void markProgressFromRow(int row) {
    final idx = _lineIndex;
    if (idx == null) return;
    final chapter = idx.chapterForRow(row);
    final lines =
        chapter == null ? null : continuousStream.bufferedLines(chapter);
    if (lines == null || lines.isEmpty) return;
    final start = idx.startRow(chapter!);
    final ordinal = row - start;
    if (ordinal < 0 || ordinal >= lines.length) return;
    final line = lines[ordinal];
    if (_state.lastReadPage == line.pageNumber &&
        _state.lastReadLine == line.lineNumber) {
      return;
    }
    final pct = idx.totalLines > 0
        ? (row / idx.totalLines).clamp(0.0, 1.0)
        : 0.0;
    _set(_state.copyWith(
      currentPage: line.pageNumber,
      lastReadPage: line.pageNumber,
      lastReadLine: line.lineNumber,
      lastPercent: pct,
    ));
    _armProgressIdleSave();
    _scheduleBackfill();
  }

  /// Debounced sequential warm-up: once the reader has been idle for
  /// [_backfillIdleDelay], every remaining chapter is buffered so later jumps
  /// and fast flings never hit a cold chapter. Each progress change resets the
  /// countdown, so it never competes with active scrolling.
  void _scheduleBackfill() {
    if (_disposed || !useContinuous || _lineIndex?.isComplete == true) return;
    _backfillTimer?.cancel();
    _backfillTimer = Timer(_backfillIdleDelay, () {
      unawaited(_runBackfill());
    });
  }

  Future<void> _runBackfill() async {
    if (_disposed || !useContinuous || _backfillRunning) return;
    if (_lineIndex?.isComplete == true) return;
    _backfillRunning = true;
    try {
      await probeAllChapters();
    } finally {
      _backfillRunning = false;
      if (!_disposed) {
        _scheduleBackfill();
      }
    }
  }

  void _armProgressIdleSave() {
    _hasUnsavedProgress = true;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 5), () {
      _flushProgressToDb();
    });
  }

  Future<void> flushProgressToDb() => _flushProgressToDb();

  Future<void> _flushProgressToDb() async {
    final book = _state.book;
    if (book == null || !_hasUnsavedProgress) return;
    _hasUnsavedProgress = false;
    await _bookService.saveProgress(
      book.id,
      _state.lastReadPage,
      _state.lastReadLine,
      _state.lastPercent,
    );
  }

  void toggleChrome() {
    _set(_state.copyWith(showChrome: !_state.showChrome));
  }

  void setVisiblePage(int page) {
    if (page == _state.currentPage) return;
    _set(_state.copyWith(currentPage: page));
  }

  void setSpreadLeftPage(int page) {
    _set(_state.copyWith(spreadLeftPage: page, currentPage: page));
  }

  /// Rebuilds the infinite-scroll buffer centered on [targetPage].
  void recenterOnPage(int targetPage, int totalPages) {
    final (prev, next) = _adjacentBuffers(targetPage, totalPages);
    _set(_state.copyWith(
      centerPage: targetPage,
      currentPage: targetPage,
      prevPages: prev,
      nextPages: next,
    ));
  }

  /// Appends one or two pages to the *down* (later) buffer.
  void extendPagesDown(int p1, int? p2) {
    final next = List<int>.of(_state.nextPages);
    next.add(p1);
    if (p2 != null) next.add(p2);
    _set(_state.copyWith(nextPages: next));
  }

  /// Appends one or two pages to the *up* (earlier) buffer.
  void extendPagesUp(int p1, int? p2) {
    final prev = List<int>.of(_state.prevPages);
    prev.add(p1);
    if (p2 != null) prev.add(p2);
    _set(_state.copyWith(prevPages: prev));
  }

  double completionForPage(int page) {
    final book = _state.book;
    if (book == null) return 0.0;
    return ReadingPositionTracker.completionForPage(
      pageNumber: page.toDouble(),
      totalPages: book.totalPages,
    );
  }

  double completionForLine(int startLine) {
    final book = _state.book;
    if (book == null) return 0.0;
    return ReadingPositionTracker.completionForLine(
      startLine: startLine.toDouble(),
      totalLines: book.totalLines,
    );
  }

  String currentChapterTitle() {
    if (useContinuous) {
      final row = _rowForLastRead();
      final idx = _lineIndex;
      final chapter = row == null || idx == null ? null : idx.chapterForRow(row);
      if (chapter != null) {
        for (final ch in _state.chapters) {
          if (ch.chapterIndex == chapter) return ch.chapterTitle;
        }
      }
    }
    return ReadingPositionTracker.chapterTitleForPage(
      _state.chapters,
      _state.currentPage,
    );
  }

  int? _rowForLastRead() {
    final idx = _lineIndex;
    if (idx == null) return null;
    final chapter =
        ReadingPositionTracker.chapterForPage(_state.chapters, _state.currentPage);
    if (chapter == null) return null;
    final lines = continuousStream.bufferedLines(chapter.chapterIndex);
    if (lines == null || lines.isEmpty) return null;
    final ordinal =
        lines.indexWhere((l) => l.pageNumber == _state.currentPage);
    if (ordinal < 0) return null;
    return idx.startRow(chapter.chapterIndex) + ordinal;
  }

  // --- Data access (routes through PageLoader / BookService) ---
  //
  // Views and the view coordinator read/fetch data through these methods rather
  // than reaching into services directly (AGENTS.md "explicit layer boundaries").

  List<BookLine>? pageCache(int page) => pageLoader.pageCache(page);
  List<BookHighlight>? highlightCache(int page) => pageLoader.highlightCache(page);
  bool isPageLoading(int page) => pageLoader.isPageLoading(page);
  bool hasPageFailed(int page) => pageLoader.hasPageFailed(page);

  /// Fetches (or returns cached) lines for [page], deduplicating in-flight load.
  Future<List<BookLine>> fetchPageLines(int page) => pageLoader.fetchPageLines(page);

  /// Preloads pages around [centerPage] via the page loader.
  Future<void> preloadAdjacentPages(
    int centerPage,
    Book book, {
    bool isDualPage = false,
    int? spreadLeftPage,
  }) =>
      pageLoader.preloadAdjacentPages(
        centerPage,
        book,
        isDualPage: isDualPage,
        spreadLeftPage: spreadLeftPage,
      );

  Future<void> invalidatePage(int page) {
    pageLoader.invalidatePage(page);
    return fetchPageLines(page);
  }

  Future<void> loadHighlightsForPage(int page) => pageLoader.loadHighlightsForPage(page);
  Future<void> saveHighlight(BookHighlight highlight) => pageLoader.saveHighlight(highlight);

  // --- Continuous scroll helpers ---

  /// Fires (and deduplicates via the stream) a chapter fetch; used by the
  /// virtual scroll content when placeholder rows scroll into view.
  void fetchChapter(int chapterIndex) {
    continuousStream.ensureChapter(chapterIndex);
  }

  /// Probes every chapter so the line index gains exact, contiguous offsets.
  /// Jumps to far chapters require this; scrolling does not.
  Future<void> probeAllChapters() async {
    final chapters = _state.chapters;
    if (chapters.isEmpty) return;
    await Future.wait([
      for (final ch in chapters)
        continuousStream.ensureChapter(ch.chapterIndex),
    ]);
  }

  /// Ensures the index allows a page jump without mis-landing: when the
  /// prefix up to the target is not yet contiguous, probess the whole book.
  Future<void> prepareForJump() async {
    final idx = _lineIndex;
    if (idx == null || idx.isComplete) return;
    await probeAllChapters();
  }

  /// Buffers chapters sequentially until the index knows the row at
  /// [targetRow], so the virtual list can scroll there exactly. No-op when the
  /// prefix is already contiguous or the book is empty.
  Future<void> ensureRowsUpTo(int targetRow) async {
    if (_disposed || !useContinuous) return;
    final idx = _lineIndex;
    if (idx == null || targetRow < 0) return;
    if (idx.knownRowCount > targetRow || idx.isComplete) return;
    final total = _state.chapters.length;
    for (var ch = 1; ch <= total; ch++) {
      if (_disposed) return;
      if (idx.knownRowCount > targetRow || idx.isComplete) return;
      await continuousStream.ensureChapter(ch);
    }
  }

  /// Converts [page] into its first global row (0-based), loading the
  /// containing chapter if needed. Returns null in degenerate cases.
  Future<int?> rowForPage(int page) async {
    final idx = _lineIndex;
    if (idx == null) return null;
    final chapter =
        ReadingPositionTracker.chapterForPage(_state.chapters, page);
    if (chapter == null) return null;
    final lines =
        await continuousStream.ensureChapter(chapter.chapterIndex);
    final start = idx.startRow(chapter.chapterIndex);
    if (lines.isEmpty) return start;
    final first = lines.indexWhere((l) => l.pageNumber == page);
    return first < 0 ? start : start + first;
  }

  /// Maps a (`page`, `line`) resume point to a global row, loading the
/// containing chapter if needed.
  Future<int> _resolveRow(List<BookChapter> chapters, int page, int line) async {
    final idx = _lineIndex;
    if (idx == null) return 0;
    final chapter =
        ReadingPositionTracker.chapterForPage(chapters, page);
    if (chapter == null) return 0;
    // Buffer earlier chapters first so the chapter start offset is exact even
    // when a deep target chapter resolves before the prefix (the index only
    // records contiguous extends).
    for (var ch = 1; ch < chapter.chapterIndex; ch++) {
      await continuousStream.ensureChapter(ch);
    }
    final start = idx.startRow(chapter.chapterIndex);
    final lines =
        await continuousStream.ensureChapter(chapter.chapterIndex);
    if (lines.isEmpty) return start;
    var ordinal =
        lines.indexWhere((l) => l.pageNumber == page && l.lineNumber >= line);
    if (ordinal < 0) {
      ordinal = lines.indexWhere((l) => l.pageNumber == page);
    }
    return ordinal < 0 ? start : start + ordinal;
  }
  void _onContinuousChapterResolved(int chapterIndex, int lineCount) {
    if (_disposed || !useContinuous) return;
    _lineIndex?.extend(chapterIndex, lineCount);
    notifyListeners();
  }

  /// Loads all highlights for [bookId] from the data layer.
  Future<List<BookHighlight>> getHighlightsForBook(String bookId) =>
      _bookService.getHighlightsForBook(bookId);

  /// Deletes a highlight by id from the data layer.
  Future<void> deleteHighlight(String highlightId) =>
      _bookService.deleteHighlight(highlightId);

  /// Builds the prev/next infinite-scroll buffer centered on [centerPage].
  static (List<int> prev, List<int> next) _adjacentBuffers(int centerPage, int totalPages) {
    final prev = <int>[];
    if (centerPage > 1) {
      prev.add(centerPage - 1);
      if (centerPage > 2) prev.add(centerPage - 2);
    }
    final next = <int>[centerPage];
    if (centerPage < totalPages) {
      next.add(centerPage + 1);
      if (centerPage + 1 < totalPages) next.add(centerPage + 2);
    }
    return (prev, next);
  }

  void _set(BookReaderState s) {
    if (_disposed) return;
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    appearance.removeListener(notifyListeners);
    _idleTimer?.cancel();
    _backfillTimer?.cancel();
    super.dispose();
  }
}
