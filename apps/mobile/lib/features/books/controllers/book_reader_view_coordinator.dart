import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/book_line.dart';
import 'book_reader_controller.dart';
import '../services/book_paragraph_grouper.dart';
import '../services/page_loader.dart';
import '../services/reading_position_tracker.dart';
import '../services/scripture_ref_parser.dart';

/// Owns the book reader's view-layer geometry and scroll coordination.
///
/// This deliberately keeps the *widget* (screen) thin and keeps *business*
/// state out of the widget tree. It is not a business controller: it holds only
/// presentation geometry — the [ScrollController], page/block [GlobalKey]s, tap
/// recognizers, and slider drag state — and translates scroll events and jumps
/// into calls on the [BookReaderController].
///
/// It communicates back to the widget through [onNeedsBuild], [isAttached], and
/// [onOpenScripture] (the widget owns the [BuildContext]).
class BookReaderViewCoordinator {
  BookReaderViewCoordinator({
    required this.controller,
    required bool Function() isDualPage,
    required VoidCallback onNeedsBuild,
    required bool Function() isAttached,
    required void Function(ParsedScriptureRef? parsed, String refText) onOpenScripture,
  })  : _isDualPage = isDualPage,
        _onNeedsBuild = onNeedsBuild,
        _isAttached = isAttached,
        _onOpenScripture = onOpenScripture {
    _scrollController.addListener(_onScroll);
  }

  final BookReaderController controller;
  final bool Function() _isDualPage;
  final VoidCallback _onNeedsBuild;
  final bool Function() _isAttached;
  final void Function(ParsedScriptureRef? parsed, String refText) _onOpenScripture;

  final ScrollController _scrollController = ScrollController();
  Key _centerKey = UniqueKey();
  final Map<int, GlobalKey> pageKeys = {};
  final Map<String, GlobalKey> blockKeys = {};
  final List<TapGestureRecognizer> tapRecognizers = [];

  bool _isLoadingDown = false;
  bool _isLoadingUp = false;
  bool _pendingResumeHandled = false;

  double? sliderDragPercent;
  int? sliderDragSpreadPage;

  ScrollController get scrollController => _scrollController;
  Key get centerKey => _centerKey;
  bool get isDualPage => _isDualPage();

  void resetCenterKey() => _centerKey = UniqueKey();

  bool get hasPendingResumeHandled => _pendingResumeHandled;
  set pendingResumeHandled(bool value) => _pendingResumeHandled = value;

  GlobalKey resolvePageKey(int page) => pageKeys[page] ??= GlobalKey();
  GlobalKey resolveBlockKey(int page, int startLine) =>
      blockKeys[ReadingBlockKey.of(page, startLine)] ??= GlobalKey();

  TapGestureRecognizer createScriptureRecognizer(ParsedScriptureRef? parsed, String refText) {
    if (tapRecognizers.length > 200) {
      final old = tapRecognizers.sublist(0, 100);
      tapRecognizers.removeRange(0, 100);
      for (final r in old) {
        r.dispose();
      }
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        _onOpenScripture(parsed, refText);
      };
    tapRecognizers.add(recognizer);
    return recognizer;
  }

  // --- Data helpers ---
  Future<List<BookLine>> fetchPageLines(int page) => controller.fetchPageLines(page);

  void invalidateAndRetry(int page) {
    controller.invalidatePage(page);
    _onNeedsBuild();
  }

  // --- Scroll coordination ---

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 800) {
      _loadMorePagesDown();
    }
    if (pos.minScrollExtent < 0 && pos.pixels <= pos.minScrollExtent + 600) {
      _loadMorePagesUp();
    }
    _updateVisiblePageAndLine();
    _pruneStaleKeys();
  }

  void _pruneStaleKeys() {
    final s = controller.state;
    final activePages = <int>{s.centerPage, ...s.prevPages, ...s.nextPages};
    pageKeys.removeWhere((page, _) => !activePages.contains(page));
    blockKeys.removeWhere((key, _) {
      final parsed = ReadingBlockKey.parse(key);
      return parsed == null || !activePages.contains(parsed.$1);
    });
  }

  void _updateVisiblePageAndLine() {
    final s = controller.state;
    final book = s.book;
    int? activeLine;
    int? activePage;
    double minDistance = double.infinity;

    for (final entry in blockKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.attached) {
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        final parsed = ReadingBlockKey.parse(entry.key);
        if (parsed == null) continue;

        if (top <= 150 && bottom >= 150) {
          activePage = parsed.$1;
          activeLine = parsed.$2;
          break;
        } else if (top > 150 && top < 600) {
          final distance = top - 150;
          if (distance < minDistance) {
            minDistance = distance;
            activePage = parsed.$1;
            activeLine = parsed.$2;
          }
        }
      }
    }

    if (activePage == null) {
      final allPages = <int>[...s.prevPages.reversed, ...s.nextPages];
      double minPageDist = double.infinity;
      for (final p in allPages) {
        final ctx = pageKeys[p]?.currentContext;
        if (ctx != null) {
          final box = ctx.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize && box.attached) {
            final top = box.localToGlobal(Offset.zero).dy;
            final bottom = top + box.size.height;
            if (top <= 250 && bottom >= 250) {
              activePage = p;
              break;
            } else if (top > 250 && top < 800) {
              final distance = top - 250;
              if (distance < minPageDist) {
                minPageDist = distance;
                activePage = p;
              }
            }
          }
        }
      }
    }

    bool shouldUpdate = false;
    if (activePage != null && activePage != s.currentPage) {
      shouldUpdate = true;
    }

    if (activeLine != null || activePage != null) {
      final page = activePage ?? s.currentPage;
      final line = activeLine ?? s.lastReadLine;
      final totalLines = book?.totalLines ?? 1;
      final percent = (line / (totalLines > 0 ? totalLines : 1)).clamp(0.0, 1.0);

      final changedPercent = (percent * 100).toInt() != (s.lastPercent * 100).toInt();
      if (shouldUpdate || changedPercent || (activeLine != null && activeLine != s.lastReadLine)) {
        controller.markProgress(page, line, percent);
      }
    }
  }

  Future<void> _loadMorePagesDown() async {
    final s = controller.state;
    if (_isLoadingDown || s.book == null) return;
    final maxPage = s.book!.totalPages;
    final currentLast = s.nextPages.isNotEmpty ? s.nextPages.last : s.centerPage;
    if (currentLast >= maxPage) return;

    _isLoadingDown = true;
    final p1 = currentLast + 1;
    final p2 = p1 + 1 <= maxPage ? p1 + 1 : null;

    await controller.fetchPageLines(p1);
    if (p2 != null) await controller.fetchPageLines(p2);

    if (_isAttached()) {
      controller.extendPagesDown(p1, p2);
      _isLoadingDown = false;
    }
  }

  Future<void> _loadMorePagesUp() async {
    final s = controller.state;
    if (_isLoadingUp || s.book == null) return;
    final currentFirst = s.prevPages.isNotEmpty ? s.prevPages.last : s.centerPage;
    if (currentFirst <= 1) return;

    _isLoadingUp = true;
    final p1 = currentFirst - 1;
    final p2 = p1 - 1 >= 1 ? p1 - 1 : null;

    await controller.fetchPageLines(p1);
    if (p2 != null) await controller.fetchPageLines(p2);

    if (_isAttached()) {
      controller.extendPagesUp(p1, p2);
      _isLoadingUp = false;
    }
  }

  void onPageFetched(int page) {
    if (_isAttached()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        checkPendingResume();
      });
    }
  }

  void schedulePendingResumeIfReady() {
    if (_pendingResumeHandled || controller.state.isLoading) return;
    if (!controller.hasPendingResume) return;
    _pendingResumeHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkPendingResume();
    });
  }

  void checkPendingResume() {
    if (!_isAttached() || !controller.hasPendingResume) return;
    final resumePage = controller.state.currentPage;
    final resumeLine = controller.lastReadLine;
    try {
      GlobalKey? blockKey = blockKeys[ReadingBlockKey.of(resumePage, resumeLine)];
      if (blockKey == null && controller.pageCache(resumePage) != null) {
        final lines = controller.pageCache(resumePage);
        if (lines != null && lines.isNotEmpty) {
          final blocks = BookParagraphGrouper.groupLines(lines);
          for (final b in blocks) {
            if (b.startLine <= resumeLine && b.endLine >= resumeLine) {
              blockKey = blockKeys[ReadingBlockKey.of(resumePage, b.startLine)];
              break;
            }
          }
        }
      }
      final blockCtx = blockKey?.currentContext;
      if (blockCtx != null && Scrollable.maybeOf(blockCtx) != null) {
        Scrollable.ensureVisible(
          blockCtx,
          duration: const Duration(milliseconds: 350),
          alignment: 0.05,
        );
        controller.clearPendingResume();
        return;
      }

      final pageKey = pageKeys[resumePage];
      final pageCtx = pageKey?.currentContext;
      final cached = controller.pageCache(resumePage);
      if (pageCtx != null &&
          Scrollable.maybeOf(pageCtx) != null &&
          cached != null &&
          cached.isNotEmpty) {
        Scrollable.ensureVisible(
          pageCtx,
          duration: const Duration(milliseconds: 350),
          alignment: 0.0,
        );
        controller.clearPendingResume();
      }
    } catch (_) {}
  }

  void _markProgressFromPage(int page, {int fallbackLine = 1}) {
    final book = controller.state.book;
    final lines = controller.pageCache(page);
    if (lines != null && lines.isNotEmpty) {
      final firstLine = lines.first.lineNumber;
      controller.markProgress(page, firstLine, controller.completionForLine(firstLine));
    } else if (book != null) {
      final percent = ReadingPositionTracker.completionForPage(
        pageNumber: page.toDouble(),
        totalPages: book.totalPages,
      );
      controller.markProgress(page, fallbackLine, percent);
    }
  }

  void turnSpread(int delta) {
    final book = controller.state.book;
    if (book == null) return;
    final totalPages = book.totalPages;
    final newLeft = (controller.state.spreadLeftPage + delta).clamp(1, totalPages);
    if (newLeft != controller.state.spreadLeftPage) {
      controller.setSpreadLeftPage(newLeft);
      _markProgressFromPage(newLeft);
      _preloadAdjacentPages(newLeft, isDualPage: true);
    }
  }

  Future<void> jumpToPage(int page) async {
    final book = controller.state.book;
    if (book == null) return;
    final targetPage = page.clamp(1, book.totalPages);

    if (_isDualPage()) {
      final newLeft = PageLoader.spreadLeftForPage(targetPage, book.totalPages);
      controller.setSpreadLeftPage(newLeft);
      _markProgressFromPage(newLeft);
      _preloadAdjacentPages(newLeft, isDualPage: true);
      return;
    }

    final key = pageKeys[targetPage];
    final ctx = key?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
      controller.setVisiblePage(targetPage);
      _markProgressFromPage(targetPage);
      return;
    }

    controller.recenterOnPage(targetPage, book.totalPages);
    _centerKey = UniqueKey();

    await controller.fetchPageLines(targetPage);
    for (final p in controller.state.prevPages) {
      controller.fetchPageLines(p);
    }
    for (final p in controller.state.nextPages) {
      controller.fetchPageLines(p);
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _markProgressFromPage(targetPage);
  }

  Future<void> _preloadAdjacentPages(int centerPage, {bool isDualPage = false}) async {
    final book = controller.state.book;
    if (book == null || !_isAttached()) return;
    await controller.preloadAdjacentPages(
      centerPage,
      book,
      isDualPage: isDualPage,
      spreadLeftPage: isDualPage ? controller.state.spreadLeftPage : null,
    );
  }

  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final r in tapRecognizers) {
      r.dispose();
    }
    tapRecognizers.clear();
  }
}
