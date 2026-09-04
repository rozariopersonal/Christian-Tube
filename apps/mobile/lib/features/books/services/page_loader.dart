import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import './book_service.dart';

/// Reads and caches book page content independently of any widget lifecycle.
///
/// Owns the in-memory page/highlight caches, deduplicates in-flight network
/// fetches, tracks pages that failed to load, and computes the pages that
/// should be preloaded around a center page for both reading layouts.
///
/// This is a pure data layer with **no `BuildContext` dependency**: it can be
/// unit-tested against a fake [BookService] subclass and reused by both the
/// single-column infinite scroll and the dual-page spread view.
class PageLoader {
  final BookService _bookService;
  final String _bookId;

  final Map<int, List<BookLine>> _pageCache = {};
  final Map<int, List<BookHighlight>> _highlightCache = {};
  final Map<int, Future<List<BookLine>>> _inFlightPageFetches = {};
  final Set<int> _failedPages = {};

  /// Callbacks invoked when a page finishes loading (success or failure) so the
  /// view can rebuild. Set by the owning controller/view.
  void Function()? onPageStateChanged;

  /// Callbacks invoked when a page that had a pending resume finishes loading.
  void Function(int page)? onPageFetched;
  int? pendingResumePage;
  int? pendingResumeLine;

  PageLoader(this._bookService, this._bookId);

  List<BookLine>? pageCache(int page) => _pageCache[page];
  List<BookHighlight>? highlightCache(int page) => _highlightCache[page];
  bool isPageLoading(int page) => _inFlightPageFetches.containsKey(page);
  bool hasPageFailed(int page) => _failedPages.contains(page);

  /// Whether [page] has content worth rendering (non-empty cache).
  bool pageAvailable(int page) {
    final lines = _pageCache[page];
    return lines != null && lines.isNotEmpty;
  }

  /// Removes cached/failed state for [page] so it will be re-fetched.
  void invalidatePage(int page) {
    _pageCache.remove(page);
    _failedPages.remove(page);
    _highlightCache.remove(page);
  }

  /// Persists a new highlight via the data adapter.
  Future<void> saveHighlight(BookHighlight highlight) =>
      _bookService.saveHighlight(highlight);

  /// Fetches highlights for [page] into the cache and marks it loaded.
  Future<void> loadHighlightsForPage(int page) async {
    final highlights = await _bookService.getHighlightsForPage(_bookId, page);
    _highlightCache[page] = highlights;
  }

  /// Returns cached lines, a service-cached page, or fetches from the adapter.
  /// Deduplicates concurrent fetches by returning the in-flight future.
  Future<List<BookLine>> fetchPageLines(int page) async {
    final cachedLines = _pageCache[page];
    if (cachedLines != null && cachedLines.isNotEmpty) {
      return cachedLines;
    }

    final serviceCached = _bookService.getCachedPageLines(_bookId, page);
    if (serviceCached != null && serviceCached.isNotEmpty) {
      _pageCache[page] = serviceCached;
      return serviceCached;
    }

    final inFlight = _inFlightPageFetches[page];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadPageLinesInternal(page);
    _inFlightPageFetches[page] = future;
    return future;
  }

  Future<List<BookLine>> _loadPageLinesInternal(int page) async {
    try {
      final lines = await _bookService.getPageLines(_bookId, page);
      final highlights = await _bookService.getHighlightsForPage(_bookId, page);
      if (lines.isNotEmpty) {
        _pageCache[page] = lines;
        _highlightCache[page] = highlights;
        _failedPages.remove(page);
      } else {
        _pageCache[page] = const [];
        _failedPages.add(page);
      }
      onPageStateChanged?.call();
      if (pendingResumePage == page && pendingResumeLine != null) {
        onPageFetched?.call(page);
      }
      return lines;
    } catch (e) {
      _pageCache[page] = const [];
      _failedPages.add(page);
      debugPrint('Error loading page $page: $e');
      onPageStateChanged?.call();
      return [];
    } finally {
      _inFlightPageFetches.remove(page);
    }
  }

  /// Preloads pages around [centerPage], prioritizing the current visible page
  /// before background pages. Behavior varies by layout ([isDualPage]).
  Future<void> preloadAdjacentPages(
    int centerPage,
    Book book, {
    bool isDualPage = false,
    int? spreadLeftPage,
  }) async {
    final total = book.totalPages;
    if (total <= 1) return;

    if (isDualPage) {
      final left = (centerPage % 2 == 0) ? (centerPage - 1).clamp(1, total) : centerPage;
      final right = (left + 1 <= total) ? left + 1 : null;

      await Future.wait([
        fetchPageLines(left),
        if (right != null) fetchPageLines(right),
      ]);

      if (spreadLeftPage != null && spreadLeftPage != left) return;

      final preloadQueue = <int>[];
      if (left + 2 <= total) preloadQueue.add(left + 2);
      if (left + 3 <= total) preloadQueue.add(left + 3);
      if (left - 1 >= 1) preloadQueue.add(left - 1);
      if (left - 2 >= 1) preloadQueue.add(left - 2);
      if (left + 4 <= total) preloadQueue.add(left + 4);
      if (left + 5 <= total) preloadQueue.add(left + 5);

      for (final p in preloadQueue) {
        if (spreadLeftPage != null && spreadLeftPage != left) break;
        if (!pageAvailable(p)) {
          await fetchPageLines(p);
        }
      }
    } else {
      await fetchPageLines(centerPage);
      final preloadQueue = <int>[];
      if (centerPage + 1 <= total) preloadQueue.add(centerPage + 1);
      if (centerPage + 2 <= total) preloadQueue.add(centerPage + 2);
      if (centerPage - 1 >= 1) preloadQueue.add(centerPage - 1);
      if (centerPage - 2 >= 1) preloadQueue.add(centerPage - 2);

      for (final p in preloadQueue) {
        if (!pageAvailable(p)) {
          await fetchPageLines(p);
        }
      }
    }
  }

  /// Computes which page pair forms a dual-page spread containing [pageNumber].
  static int spreadLeftForPage(int pageNumber, int totalPages) {
    final clamped = pageNumber.clamp(1, totalPages);
    return (clamped % 2 == 0) ? (clamped - 1).clamp(1, totalPages) : clamped;
  }

  /// Clears all in-memory caches (used rarely, e.g. language/theme resets).
  void clearAll() {
    _pageCache.clear();
    _highlightCache.clear();
    _failedPages.clear();
  }
}
