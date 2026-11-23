import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile/shared/ui/reader_selection_line.dart';
import 'package:mobile/features/books/services/book_highlight_ranges.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/services/reader_fullscreen_service.dart';
import '../controllers/book_reader_controller.dart';
import '../controllers/book_reader_view_coordinator.dart';
import '../models/book_highlight.dart';
import '../services/book_service.dart';
import '../services/book_paragraph_grouper.dart';
import '../services/reading_position_tracker.dart';
import '../services/scripture_ref_parser.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../../../shared/ui/floating_selection_bar.dart';
import '../../../../shared/ui/reader_appearance_sheet.dart';
import '../widgets/book_highlights_sheet.dart';
import '../widgets/book_toc_sheet.dart';
import '../widgets/book_virtual_scroll_content.dart';
import '../widgets/book_reader_zoom_canvas.dart';
import '../widgets/block_builder.dart';
import '../widgets/dual_page_spread_view.dart';
import '../widgets/mobile_page_view.dart';
import '../widgets/reader_appbar.dart';
import '../widgets/reader_navigation_bar.dart';
import '../widgets/reader_selection_toolbar.dart';
import '../widgets/scripture_verse_popup.dart';
import '../../../../shared/ui/reader_fullscreen_button.dart';

/// Adaptive reading screen featuring:
/// - Horizontal swiping page view for mobile screens
/// - Side-by-side dual-page spread view for large screens (tablets/desktop)
/// - Continuous whole-book scroll (virtualized, on-demand chapters)
/// - Cross-device and cross-size exact line resumability
/// - Persists reading position to SQLite upon app close / backgrounding and after 5 minutes of idleness
/// - Typography controls (Serif/Sans, font size, line-height) and 4 reading themes
/// - Text highlighting with 4 colors, persisted to SQLite
/// - Inline scripture link detection with popover previews
/// - Integrated dictionary lookup on text selection
///
/// This screen is intentionally thin: behavioral state lives in
/// [BookReaderController], and all view-layer geometry (GlobalKeys,
/// PageController, selection recognizers, continuous scroll controllers) lives
/// in [BookReaderViewCoordinator]. This widget only assembles the two and their
/// sub-views.
class BookReaderScreen extends StatefulWidget {
  final String bookId;
  final int? initialPage;
  final int? initialLine;
  final int? highlightStartLine;
  final int? highlightEndLine;

  /// When true the reader renders the continuous whole-book scroll instead of
  /// the paged views. Now the default; pass `false` to force the legacy paged
  /// reader for a specific route.
  final bool useContinuous;

  const BookReaderScreen({
    super.key,
    required this.bookId,
    this.initialPage,
    this.initialLine,
    this.highlightStartLine,
    this.highlightEndLine,
    this.useContinuous = true,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> with WidgetsBindingObserver {
  static const String _readerId = 'book';
  final ReaderFullscreenService _fullscreen = ReaderFullscreenService.instance;
  late BookReaderController _controller;
  late BookReaderViewCoordinator _coordinator;
  bool _isPopping = false;
  BookHighlight? _selectedHighlight;
  final Map<String, ({int page, int startLine, int endLine, String text, SelectedContentRange range})> _bookSelection = {};
  final Set<int> _loadingHighlightPages = {};

  bool get _isDualPage => ScreenClass.of(context) == ScreenClass.expanded;

  @override
  void initState() {
    super.initState();
    _fullscreen.attach(_readerId);
    WidgetsBinding.instance.addObserver(this);
    // Prewarm localized book names so scripture references inside the book
    // (in any supported language) resolve to tappable verse popups.
    BookNameService().ensureLoaded().then((_) {
      ScriptureRefParser.refreshRuntimeBookNumbers();
    });
    _controller = BookReaderController(
      BookService.instance,
      widget.bookId,
      initialPage: widget.initialPage,
      initialLine: widget.initialLine,
      highlightStartLine: widget.highlightStartLine,
      useContinuous: widget.useContinuous,
    );
    _coordinator = BookReaderViewCoordinator(
      controller: _controller,
      isDualPage: () => _isDualPage,
      onNeedsBuild: () {
        if (mounted) setState(() {});
      },
      isAttached: () => mounted,
      onOpenScripture: (parsed, refText) {
        if (parsed != null) {
          ScriptureVersePopup.show(
            context,
            bookNumber: parsed.bookNumber,
            chapter: parsed.chapter,
            startVerse: parsed.startVerse,
            endVerse: parsed.endVerse,
            rawReference: refText,
            languageCode: _controller.state.book?.language ??
                _controller.appearance.languageCode,
          );
        }
      },
    );
    _controller.appearance.loadFromPrefs().then((_) {
      if (mounted) setState(() {});
    });
    _controller.pageLoader.onPageStateChanged = () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    };
    _controller.pageLoader.onPageFetched = _coordinator.onPageFetched;
    _controller.addListener(_onControllerChanged);
    _controller.load();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    _coordinator.schedulePendingResumeIfReady();
  }

  /// Single back path for the reader (system back, AppBar chevron and the
  /// "Go Back" error action funnel here): persist the reading position first,
  /// then always pop so a failing flush can never strand the user on the
  /// reader page.
  Future<void> _handleBack(Object? result) async {
    if (_fullscreen.isFullscreenFor(_readerId)) {
      _fullscreen.exit(_readerId);
      return;
    }
    if (!_controller.state.showChrome) {
      _controller.toggleChrome();
      return;
    }
    if (_isPopping) return;
    _isPopping = true;
    try {
      await _controller.flushProgressToDb();
    } catch (e) {
      debugPrint('Error flushing reading progress: $e');
    } finally {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(result);
        } else {
          context.go('/books');
        }
      }
    }
  }

  @override
  void dispose() {
    _fullscreen.detach(_readerId);
    WidgetsBinding.instance.removeObserver(this);
    if (_controller.hasUnsavedProgress) {
      unawaited(_controller.flushProgressToDb());
    }
    _coordinator.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _controller.flushProgressToDb();
    }
  }

  void _openToc(bool isExpanded) {
    final s = _controller.state;
    if (s.book == null) return;
    BookTocSheet.show(
      context,
      bookTitle: s.book!.title,
      chapters: s.chapters,
      currentPage: s.currentPage,
      showPageNumbers: isExpanded,
      onSelectPage: _coordinator.jumpToPage,
    );
  }

  Future<void> _openHighlights() async {
    final s = _controller.state;
    if (s.book == null) return;

    await _controller.loadHighlightsForPage(s.currentPage);

    BookHighlightsSheet.show(
      context,
      controller: _controller,
      bookId: s.book!.id,
      bookTitle: s.book!.title,
      onSelectPage: _coordinator.jumpToPage,
    );
  }

  void _showAppearanceSheet(BuildContext context) {
    showReaderAppearanceSheet(context, _controller.appearance);
  }

  Future<void> _createHighlight(String text, int startChar, int pageNum, {int color = 0}) async {
    final s = _controller.state;
    if (s.book == null) return;
    final selections = _bookSelection.values.toList();
    var saved = 0;
    for (final selection in selections) {
      final lines = await _controller.fetchPageLines(selection.page);
      final source = lines.where((line) => line.lineNumber >= selection.startLine &&
          line.lineNumber <= selection.endLine);
      for (final span in BookHighlightRanges.lineSpans(selection.text, source)) {
        final start = selection.range.startOffset.clamp(span.start, span.end);
        final end = selection.range.endOffset.clamp(span.start, span.end);
        if (start >= end) continue;
        final highlight = BookHighlight(
          id: 'book_range_${span.line.lineNumber}_${DateTime.now().microsecondsSinceEpoch}_$saved',
          bookId: s.book!.id,
          chapterIndex: span.line.chapterIndex,
          pageNumber: selection.page,
          startChar: start - span.start,
          endChar: end - span.start,
          text: selection.text.substring(start, end),
          color: color,
          createdAt: DateTime.now().toIso8601String(),
        );
        await _controller.saveHighlight(highlight);
        saved++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved == 0 ? 'Select book text to highlight.' : 'Highlight saved'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Widget _trackBookSelection({required int page, required int startLine,
      required int endLine, required String text, required Widget child}) {
    final key = '$page:$startLine:$endLine';
    return ReaderSelectionLine(
      key: ValueKey('book-selection-$key'),
      onSelection: (range) {
        if (range == null || range.startOffset == range.endOffset) {
          _bookSelection.remove(key);
        } else {
          _bookSelection[key] = (page: page, startLine: startLine,
              endLine: endLine, text: text, range: range);
        }
      },
      child: child,
    );
  }

  List<BookHighlight> _continuousHighlights(int page) {
    final cached = _controller.pageLoader.highlightCache(page);
    if (cached != null) return cached;
    if (_loadingHighlightPages.add(page)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _controller.loadHighlightsForPage(page);
          if (mounted) setState(() {});
        } finally {
          _loadingHighlightPages.remove(page);
        }
      });
    }
    return const [];
  }

  TapGestureRecognizer _makeHighlightRecognizer(BookHighlight highlight) {
    final r = TapGestureRecognizer()
      ..onTap = () {
        if (!mounted) return;
        setState(() {
          _selectedHighlight =
              _selectedHighlight?.id == highlight.id ? null : highlight;
        });
      };
    _coordinator.tapRecognizers.add(r);
    return r;
  }

  Future<void> _recolorSelectedHighlight(
      BookHighlight h, int colorIndex) async {
    final updated = BookHighlight(
      id: h.id,
      bookId: h.bookId,
      chapterIndex: h.chapterIndex,
      pageNumber: h.pageNumber,
      startChar: h.startChar,
      endChar: h.endChar,
      text: h.text,
      color: colorIndex,
      createdAt: h.createdAt,
    );
    await _controller.saveHighlight(updated);
    await _controller.loadHighlightsForPage(h.pageNumber);
    if (mounted) setState(() => _selectedHighlight = null);
  }

  Future<void> _deleteSelectedHighlight(BookHighlight h) async {
    await _controller.deleteHighlight(h.id);
    await _controller.loadHighlightsForPage(h.pageNumber);
    if (mounted) setState(() => _selectedHighlight = null);
  }

  Widget _buildSelectionToolbar(BuildContext context, SelectableRegionState selectableRegionState, int pageNum, String selectedText) {
    return buildReaderSelectionToolbar(
      context,
      selectableRegionState,
      pageNum,
      selectedText: selectedText,
      onHighlight: (text, page) => _createHighlight(text, 0, page, color: 0),
      onHighlightWithColor: (text, page, colorIndex) =>
          _createHighlight(text, 0, page, color: colorIndex),
    );
  }

  Widget _buildMobilePageView(AppTokens tokens) {
    return MobilePageView(
      tokens: tokens,
      controller: _controller,
      appearance: _controller.appearance,
      pageController: _coordinator.pageController,
      onToggleChrome: _controller.toggleChrome,
      onTriggerFetch: _coordinator.fetchPageLines,
      onRetry: _coordinator.invalidateAndRetry,
      buildSelectionToolbar: _buildSelectionToolbar,
      buildBlock: _buildBlockWidget,
      onPageChanged: _coordinator.handlePageChanged,
    );
  }

  Widget _buildDualPageSpreadView(AppTokens tokens) {
    return DualPageSpreadView(
      tokens: tokens,
      controller: _controller,
      appearance: _controller.appearance,
      onTurnSpread: _coordinator.turnSpread,
      onToggleChrome: _controller.toggleChrome,
      onTriggerFetch: _coordinator.fetchPageLines,
      onRetry: _coordinator.invalidateAndRetry,
      buildSelectionToolbar: _buildSelectionToolbar,
      buildBlock: _buildBlockWidget,
    );
  }

  Widget _buildContinuousContent(AppTokens tokens) {
    final s = _controller.state;
    final appearance = _controller.appearance;
    final index = _controller.lineIndex;
    if (s.book == null || index == null) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }
    return MaxWidthBox(
      maxWidth: kReadingMaxWidth,
      child: BookVirtualScrollContent(
        totalLines: s.book!.totalLines,
        totalChapters: s.chapters.length,
        index: index,
        isChapterLoaded: _controller.continuousStream.contains,
        chapterLines: _controller.continuousStream.bufferedLines,
        highlightCache: _continuousHighlights,
        appearance: appearance,
        tokens: tokens,
        textColor: appearance.textColor(tokens),
        itemScrollController: _coordinator.itemScrollController,
        itemPositionsListener: _coordinator.itemPositionsListener,
        makeRecognizer: _coordinator.createScriptureRecognizer,
        makeHighlightRecognizer: _makeHighlightRecognizer,
        onTriggerFetch: _controller.fetchChapter,
        wrapLine: (line, child) =>
            BookParagraphGrouper.blockFromLine(line).type == 'chapter_header'
                ? child
                : _trackBookSelection(
          page: line.pageNumber, startLine: line.lineNumber,
          endLine: line.lineNumber, text: line.text.trim(), child: child),
        buildSelectionToolbar: (context, state, text) =>
            _buildSelectionToolbar(context, state, s.currentPage, text),
      ),
    );
  }

  Widget _buildBlockWidget(
    BookRenderBlock block,
    int pageNum,
    Color textColor,
    AppTokens tokens,
  ) {
    final appearance = _controller.appearance;
    final pageHighlights = _controller.pageLoader.highlightCache(pageNum) ?? const [];
    final child = BookBlockWidget(
      block: block,
      pageNum: pageNum,
      bookId: _controller.state.book?.id ?? '',
      textColor: textColor,
      tokens: tokens,
      appearance: appearance,
      highlightStartLine: widget.highlightStartLine,
      highlightEndLine: widget.highlightEndLine,
      highlightCache: pageHighlights,
      sourceLines: (_controller.pageCache(pageNum) ?? const []).where((line) =>
          line.lineNumber >= block.startLine && line.lineNumber <= block.endLine).toList(),
      resolveBlockKey: _coordinator.resolveBlockKey,
      makeRecognizer: _coordinator.createScriptureRecognizer,
      makeHighlightRecognizer: _makeHighlightRecognizer,
    );
    if (block.type == 'chapter_header' || block.type == 'img') return child;
    return _trackBookSelection(page: pageNum, startLine: block.startLine,
        endLine: block.endLine, text: block.text, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final appearance = _controller.appearance;
    final s = _controller.state;
    final bgColor = appearance.background(tokens);
    final totalPages = ReadingPositionTracker.safeTotalPages(s.book);
    final continuous = _controller.useContinuous;
    final isDualPage = _isDualPage && !continuous;

    final validLeftPage = s.spreadLeftPage.clamp(1, totalPages);
    final rightPage = validLeftPage + 1 <= totalPages ? validLeftPage + 1 : null;

    return ListenableBuilder(
      listenable: Listenable.merge([appearance, _fullscreen]),
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBack(result);
        },
        child: Listener(
          onPointerDown: (_) => _fullscreen.noteActivity(_readerId),
          child: Scaffold(
          backgroundColor: bgColor,
          appBar: s.showChrome && !_fullscreen.isFullscreenFor(_readerId)
              ? BookReaderAppBar(
                  controller: _controller,
                  tokens: tokens,
                  bgColor: bgColor,
                  isDualPage: isDualPage,
                  validLeftPage: validLeftPage,
                  rightPage: rightPage,
                  totalPages: totalPages,
                  onOpenToc: () => _openToc(isDualPage),
                  onOpenHighlights: _openHighlights,
                  onShowAppearance: () => _showAppearanceSheet(context),
                  onToggleFullscreen: () => _fullscreen.toggle(_readerId),
                )
              : null,
          body: s.isLoading
              ? Center(child: CircularProgressIndicator(color: tokens.accent))
              : s.book == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, size: 48, color: tokens.onSurfaceMuted.withValues(alpha: 0.6)),
                            const SizedBox(height: 16),
                            Text(
                              'Book not found',
                              style: TextStyle(color: tokens.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This book could not be located in the catalog.',
                              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.local_library_outlined, size: 16),
                              label: const Text('Return to Library'),
                              onPressed: () => _handleBack(null),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        BookReaderZoomCanvas(
                          controller: _coordinator.zoomController,
                          child: continuous
                              ? _buildContinuousContent(tokens)
                              : isDualPage
                                  ? _buildDualPageSpreadView(tokens)
                                  : _buildMobilePageView(tokens),
                        ),
                        if (_selectedHighlight != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: Center(
                              child: FloatingSelectionBar(
                                currentColorIndex: _selectedHighlight!.color,
                                hasHighlight: true,
                                onSwatch: (c) => _recolorSelectedHighlight(
                                  _selectedHighlight!,
                                  c,
                                ),
                                onClearHighlight: () => _deleteSelectedHighlight(
                                  _selectedHighlight!,
                                ),
                                onDismiss: () =>
                                    setState(() => _selectedHighlight = null),
                                actions: [
                                  SelectionBarAction(
                                    icon: Icons.copy_rounded,
                                    tooltip: 'Copy',
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: _selectedHighlight!.text,
                                        ),
                                      );
                                      setState(() => _selectedHighlight = null);
                                    },
                                  ),
                                  SelectionBarAction(
                                    icon: Icons.ios_share_rounded,
                                    tooltip: 'Share',
                                    onTap: () {
                                      final txt = _selectedHighlight!.text;
                                      setState(() => _selectedHighlight = null);
                                      Share.share(txt);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_fullscreen.isFullscreenFor(_readerId))
                          ReaderFullscreenButton(
                            onExit: () => _fullscreen.exit(_readerId),
                          ),
                      ],
                    ),
          bottomNavigationBar: s.showChrome &&
                  s.book != null &&
                  !_fullscreen.isFullscreenFor(_readerId)
              ? ReaderNavigationBar(
                  controller: _controller,
                  tokens: tokens,
                  bgColor: bgColor,
                  isDualPage: isDualPage,
                  totalPages: totalPages,
                  validLeftPage: validLeftPage,
                  rightPage: rightPage,
                  onPrevious: () {
                    if (isDualPage) {
                      _coordinator.turnSpread(-2);
                    } else if (s.currentPage > 1) {
                      _coordinator.jumpToPage(s.currentPage - 1);
                    }
                  },
                  onNext: () {
                    if (isDualPage) {
                      _coordinator.turnSpread(2);
                    } else if (s.currentPage < totalPages) {
                      _coordinator.jumpToPage(s.currentPage + 1);
                    }
                  },
                )
              : null,
          ),
        ),
      ),
    );
  }
}
