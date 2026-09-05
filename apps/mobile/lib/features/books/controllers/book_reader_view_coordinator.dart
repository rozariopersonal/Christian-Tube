import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/book_line.dart';
import 'book_reader_controller.dart';
import '../services/book_paragraph_grouper.dart';
import '../services/page_loader.dart';
import '../services/reading_position_tracker.dart';
import '../services/scripture_ref_parser.dart';

/// Owns the book reader's view-layer coordination.
///
/// Manages tap recognizers, block keys for scroll-to-resume logic, and the
/// [PageController] for horizontal swiping on mobile devices. In continuous
/// mode it also owns the [ItemScrollController] / [ItemPositionsListener] of
/// the virtual scroll body and converts page targets into global rows.
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
    _pageController = PageController(initialPage: (controller.state.currentPage - 1).clamp(0, 999999));
    itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  final BookReaderController controller;
  final bool Function() _isDualPage;
  final VoidCallback _onNeedsBuild;
  final bool Function() _isAttached;
  final void Function(ParsedScriptureRef? parsed, String refText) _onOpenScripture;

  late final PageController _pageController;
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();
  final Map<int, GlobalKey> pageKeys = {};
  final Map<String, GlobalKey> blockKeys = {};
  final List<TapGestureRecognizer> tapRecognizers = [];

  bool _pendingResumeHandled = false;
  int _lastHandledRow = -1;

  PageController get pageController => _pageController;
  bool get isDualPage => _isDualPage();

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

    if (controller.useContinuous) {
      unawaited(_performContinuousResume());
      return;
    }

    // Jump the PageController to the correct page if needed
    if (!_isDualPage()) {
      if (_pageController.hasClients) {
        final targetPageIdx = resumePage - 1;
        if (_pageController.page?.round() != targetPageIdx) {
          _pageController.jumpToPage(targetPageIdx);
        }
      } else {
        _pendingResumeHandled = false;
        return;
      }
    }

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

  /// Continuous-mode resume: buffers every row up to the target so the line
  /// index has contiguous offsets, then scrolls there. Retries on later frames
  /// until the virtual list is attached (mirrors the Bible reader's pattern).
  Future<void> _performContinuousResume() async {
    if (!controller.hasPendingResume) return;
    final resumeRow = controller.state.resumeRow;
    if ((controller.state.book?.totalLines ?? 0) == 0) {
      controller.clearPendingResume();
      return;
    }
    await controller.ensureRowsUpTo(resumeRow);
    if (!controller.hasPendingResume) return;
    if (!itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.useContinuous) {
          unawaited(_performContinuousResume());
        }
      });
      return;
    }
    _jumpToRow(resumeRow);
    controller.clearPendingResume();
  }

  void _markProgressFromPage(int page, {int fallbackLine = 1}) {
    final lines = controller.pageCache(page);
    final currentLine = (lines != null && lines.isNotEmpty)
        ? lines.first.lineNumber
        : fallbackLine;
    final percent = controller.completionForPage(page);
    controller.markProgress(page, currentLine, percent);
  }

  void handlePageChanged(int page) {
    if (controller.state.currentPage == page) return;
    controller.setVisiblePage(page);
    _markProgressFromPage(page);
    _preloadAdjacentPages(page, isDualPage: false);
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

    if (controller.useContinuous) {
      await controller.prepareForJump();
      final row = await controller.rowForPage(targetPage);
      if (row == null || !_isAttached()) return;
      controller.clearPendingResume();
      _jumpToRow(row);
      return;
    }

    if (_isDualPage()) {
      final newLeft = PageLoader.spreadLeftForPage(targetPage, book.totalPages);
      controller.setSpreadLeftPage(newLeft);
      _markProgressFromPage(newLeft);
      _preloadAdjacentPages(newLeft, isDualPage: true);
      return;
    }

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        targetPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _jumpToRow(int row, {bool animated = true}) {
    if (!itemScrollController.isAttached) return;
    final total = controller.state.book?.totalLines ?? 0;
    var target = row < 0 ? 0 : row;
    if (total > 0 && target >= total) target = total - 1;
    if (target < 0) return;
    itemScrollController.scrollTo(
      index: target,
      alignment: 0.0,
      duration: animated ? const Duration(milliseconds: 350) : const Duration(milliseconds: 1),
    );
  }

  /// Continuous-mode handler for the virtual list positions: reports progress
  /// from the leading visible row and streams chapters reaching the viewport.
  void _onItemPositionsChanged() {
    if (!controller.useContinuous || !_isAttached()) return;
    final idx = controller.lineIndex;
    if (idx == null) return;
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    ItemPosition? lead;
    for (final p in positions) {
      if (lead == null || p.itemLeadingEdge < lead.itemLeadingEdge) {
        lead = p;
      }
    }
    if (lead == null || lead.index < 0) return;
    if (lead.index == _lastHandledRow) return;
    _lastHandledRow = lead.index;

    controller.markProgressFromRow(lead.index);

    final chapter = idx.chapterForRow(lead.index);
    if (chapter == null) return;

    controller.continuousStream.preloadAround(
      chapter,
      radius: chapter == 0 ? 2 : 1,
    );
    for (final p in positions) {
      final c = idx.chapterForRow(p.index);
      if (c != null && !controller.continuousStream.contains(c)) {
        controller.fetchChapter(c);
      }
    }
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
    _pageController.dispose();
    for (final r in tapRecognizers) {
      r.dispose();
    }
    tapRecognizers.clear();
  }
}

