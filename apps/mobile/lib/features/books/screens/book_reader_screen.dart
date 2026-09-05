import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/book_reader_controller.dart';
import '../controllers/book_reader_view_coordinator.dart';
import '../models/book_highlight.dart';
import '../services/book_service.dart';
import '../services/book_paragraph_grouper.dart';
import '../services/reading_position_tracker.dart';
import '../../../../shared/ui/reader_appearance_sheet.dart';
import '../widgets/book_highlights_sheet.dart';
import '../widgets/book_toc_sheet.dart';
import '../widgets/book_virtual_scroll_content.dart';
import '../widgets/block_builder.dart';
import '../widgets/dual_page_spread_view.dart';
import '../widgets/mobile_page_view.dart';
import '../widgets/reader_appbar.dart';
import '../widgets/reader_navigation_bar.dart';
import '../widgets/reader_selection_toolbar.dart';
import '../widgets/scripture_verse_popup.dart';

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
    this.highlightStartLine,
    this.highlightEndLine,
    this.useContinuous = true,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> with WidgetsBindingObserver {
  late BookReaderController _controller;
  late BookReaderViewCoordinator _coordinator;
  bool _isPopping = false;

  bool get _isDualPage => ScreenClass.of(context) == ScreenClass.expanded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BookReaderController(
      BookService.instance,
      widget.bookId,
      initialPage: widget.initialPage,
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
          );
        }
      },
    );
    _controller.appearance.loadFromPrefs();
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

  @override
  void dispose() {
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
    if (s.book == null || text.trim().isEmpty) return;

    int chapterIndex = 1;
    for (final ch in s.chapters) {
      if (pageNum >= ch.startPage && pageNum <= ch.endPage) {
        chapterIndex = ch.chapterIndex;
        break;
      }
    }

    final highlight = BookHighlight(
      id: '${s.book!.id}_${pageNum}_${DateTime.now().millisecondsSinceEpoch}',
      bookId: s.book!.id,
      chapterIndex: chapterIndex,
      pageNumber: pageNum,
      startChar: startChar,
      endChar: startChar + text.length,
      text: text,
      color: color,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _controller.saveHighlight(highlight);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Highlight saved'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildSelectionToolbar(BuildContext context, SelectableRegionState selectableRegionState, int pageNum) {
    return buildReaderSelectionToolbar(
      context,
      selectableRegionState,
      pageNum,
      onHighlight: (text, page) => _createHighlight(text, 0, page, color: 0),
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
      maxWidth: kContentMaxWidth,
      child: BookVirtualScrollContent(
        totalLines: s.book!.totalLines,
        totalChapters: s.chapters.length,
        index: index,
        isChapterLoaded: _controller.continuousStream.contains,
        chapterLines: _controller.continuousStream.bufferedLines,
        highlightCache: (page) =>
            _controller.pageLoader.highlightCache(page) ?? const [],
        appearance: appearance,
        tokens: tokens,
        textColor: appearance.textColor(tokens),
        itemScrollController: _coordinator.itemScrollController,
        itemPositionsListener: _coordinator.itemPositionsListener,
        makeRecognizer: _coordinator.createScriptureRecognizer,
        onTriggerFetch: _controller.fetchChapter,
        buildSelectionToolbar: (context, state) =>
            _buildSelectionToolbar(context, state, s.currentPage),
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
    return BookBlockWidget(
      block: block,
      pageNum: pageNum,
      textColor: textColor,
      tokens: tokens,
      appearance: appearance,
      highlightStartLine: widget.highlightStartLine,
      highlightEndLine: widget.highlightEndLine,
      highlightCache: pageHighlights,
      resolveBlockKey: _coordinator.resolveBlockKey,
      makeRecognizer: _coordinator.createScriptureRecognizer,
    );
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isPopping) return;
        _isPopping = true;
        await _controller.flushProgressToDb();
        if (context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: s.showChrome
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
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text('Go Back'),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                  )
: continuous
                      ? _buildContinuousContent(tokens)
                      : isDualPage
                          ? _buildDualPageSpreadView(tokens)
                          : _buildMobilePageView(tokens),
        bottomNavigationBar: s.showChrome && s.book != null
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
    );
  }
}
