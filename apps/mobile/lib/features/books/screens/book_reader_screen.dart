import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../dictionary/widgets/inline_dictionary_popover.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import '../services/book_paragraph_grouper.dart';
import '../services/book_service.dart';
import '../services/scripture_ref_parser.dart';
import '../widgets/book_highlights_sheet.dart';
import '../widgets/book_toc_sheet.dart';
import '../widgets/scripture_verse_popup.dart';

enum ReaderThemeMode { system, paper, sepia, dark, amoled }

/// Adaptive reading screen featuring:
/// - Continuous two-way vertical infinite scroll for mobile screens without page numbers
/// - Side-by-side dual-page spread view for large screens (tablets/desktop) with page numbers
/// - Cross-device and cross-size exact line resumability
/// - Persists reading position to SQLite upon app close / backgrounding and after 5 minutes of idleness
/// - Typography controls (Serif/Sans, font size, line-height) and 4 reading themes
/// - Text highlighting with 4 colors, persisted to SQLite
/// - Inline scripture link detection with popover previews
/// - Integrated dictionary lookup on text selection
class BookReaderScreen extends StatefulWidget {
  final String bookId;
  final int? initialPage;
  final int? highlightStartLine;
  final int? highlightEndLine;

  const BookReaderScreen({
    super.key,
    required this.bookId,
    this.initialPage,
    this.highlightStartLine,
    this.highlightEndLine,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> with WidgetsBindingObserver {
  final BookService _bookService = BookService.instance;
  late final ScrollController _scrollController;

  Book? _book;
  List<BookChapter> _chapters = [];
  bool _isLoading = true;
  int _currentPage = 1;
  bool _showChrome = true;

  // Persisted reading position
  int _lastReadPage = 1;
  int _lastReadLine = 1;
  double _lastPercent = 0.0;
  bool _hasUnsavedProgress = false;
  Timer? _idleTimer;

  // Dual-page spread state (for large screens: ScreenClass.expanded / width >= 840)
  int _spreadLeftPage = 1;

  // Infinite scroll two-way pagination state (for mobile screens: single column)
  late int _centerPage;
  late Key _centerKey;
  final List<int> _prevPages = [];
  final List<int> _nextPages = [];
  final Map<int, GlobalKey> _pageKeys = {};
  final Map<int, GlobalKey> _blockKeys = {}; // Key per startLine for exact paragraph resume
  bool _isLoadingDown = false;
  bool _isLoadingUp = false;

  // Reading appearance settings
  double _fontSize = 17.0;
  final double _lineHeight = 1.65;
  bool _useSerifFont = true;
  ReaderThemeMode _themeMode = ReaderThemeMode.system;

  // In-memory page & highlight cache for instantaneous rendering
  final Map<int, List<BookLine>> _pageCache = {};
  final Map<int, List<BookHighlight>> _highlightCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPage = widget.initialPage ?? 1;
    _centerPage = _currentPage;
    _centerKey = UniqueKey();
    _nextPages.add(_centerPage);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadBook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _flushProgressToDb();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _flushProgressToDb();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // 1. Infinite scroll DOWN: load next pages when near bottom
    if (pos.pixels >= pos.maxScrollExtent - 800) {
      _loadMorePagesDown();
    }

    // 2. Infinite scroll UP: load previous pages when near top
    if (pos.pixels <= pos.minScrollExtent + 600) {
      _loadMorePagesUp();
    }

    // 3. Track currently visible page & line in viewport
    _updateVisiblePageAndLine();
  }

  void _updateVisiblePageAndLine() {
    // 1. First find the active reading block (around Y = 80..220px)
    int? activeLine;
    int? activePage;

    for (final entry in _blockKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        if (top <= 200 && bottom >= 90) {
          activeLine = entry.key;
          break;
        }
      }
    }

    // 2. Also track active page
    final allPages = <int>[];
    for (int i = _prevPages.length - 1; i >= 0; i--) {
      allPages.add(_prevPages[i]);
    }
    allPages.addAll(_nextPages);

    for (final p in allPages) {
      final key = _pageKeys[p];
      final ctx = key?.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final top = box.localToGlobal(Offset.zero).dy;
          final bottom = top + box.size.height;
          if (top <= 300 && bottom >= 100) {
            activePage = p;
            break;
          }
        }
      }
    }

    if (activePage != null && activePage != _currentPage) {
      setState(() => _currentPage = activePage!);
    }

    if (activeLine != null || activePage != null) {
      final page = activePage ?? _currentPage;
      final line = activeLine ?? _lastReadLine;
      final totalLines = _book?.totalLines ?? 1;
      final percent = (line / (totalLines > 0 ? totalLines : 1)).clamp(0.0, 1.0);
      _markProgressChanged(page, line, percent);
    }
  }

  void _markProgressChanged(int page, int line, double percent) {
    _lastReadPage = page;
    _lastReadLine = line;
    _lastPercent = percent;
    _hasUnsavedProgress = true;

    // Persist in database after 5 minutes of idleness
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 5), () {
      _flushProgressToDb();
    });
  }

  Future<void> _flushProgressToDb() async {
    if (_book == null || !_hasUnsavedProgress) return;
    _hasUnsavedProgress = false;
    await _bookService.saveProgress(
      _book!.id,
      _lastReadPage,
      _lastReadLine,
      _lastPercent,
    );
  }

  Future<void> _loadMorePagesDown() async {
    if (_isLoadingDown || _book == null) return;
    final maxPage = _book!.totalPages;
    final currentLast = _nextPages.isNotEmpty ? _nextPages.last : _centerPage;
    if (currentLast >= maxPage) return;

    _isLoadingDown = true;
    final p1 = currentLast + 1;
    final p2 = p1 + 1 <= maxPage ? p1 + 1 : null;

    await _fetchPageLines(p1);
    if (p2 != null) await _fetchPageLines(p2);

    if (mounted) {
      setState(() {
        _nextPages.add(p1);
        if (p2 != null) _nextPages.add(p2);
        _isLoadingDown = false;
      });
    }
  }

  Future<void> _loadMorePagesUp() async {
    if (_isLoadingUp || _book == null) return;
    final currentFirst = _prevPages.isNotEmpty ? _prevPages.last : _centerPage;
    if (currentFirst <= 1) return;

    _isLoadingUp = true;
    final p1 = currentFirst - 1;
    final p2 = p1 - 1 >= 1 ? p1 - 1 : null;

    await _fetchPageLines(p1);
    if (p2 != null) await _fetchPageLines(p2);

    if (mounted) {
      setState(() {
        _prevPages.add(p1);
        if (p2 != null) _prevPages.add(p2);
        _isLoadingUp = false;
      });
    }
  }

  Future<void> _loadBook() async {
    final book = await _bookService.getBook(widget.bookId);
    final chapters = await _bookService.getChapters(widget.bookId);

    if (book != null) {
      // 1. Resolve initial resume position
      int initialPage = widget.initialPage ?? 1;
      int initialLine = widget.highlightStartLine ?? 1;

      if (widget.initialPage == null) {
        final saved = await _bookService.getProgress(widget.bookId);
        if (saved != null) {
          initialPage = saved.currentPage.clamp(1, book.totalPages);
          initialLine = saved.currentLine;
          _lastPercent = saved.completionPercent;
        }
      }

      _lastReadPage = initialPage;
      _lastReadLine = initialLine;
      _currentPage = initialPage;
      _centerPage = initialPage;
      _centerKey = UniqueKey();

      // For dual-page spread (1 & 2, 3 & 4, 5 & 6...):
      _spreadLeftPage = (initialPage % 2 == 0)
          ? (initialPage - 1).clamp(1, book.totalPages)
          : initialPage;

      _prevPages.clear();
      if (initialPage > 1) {
        _prevPages.add(initialPage - 1);
        if (initialPage > 2) _prevPages.add(initialPage - 2);
      }

      _nextPages.clear();
      _nextPages.add(initialPage);
      if (initialPage < book.totalPages) {
        _nextPages.add(initialPage + 1);
        if (initialPage + 1 < book.totalPages) _nextPages.add(initialPage + 2);
      }

      if (mounted) {
        setState(() {
          _book = book;
          _chapters = chapters;
          _isLoading = false;
        });
      }

      // Pre-warm center and adjacent pages
      await _fetchPageLines(initialPage);
      if (initialPage < book.totalPages) await _fetchPageLines(initialPage + 1);
      for (final p in _prevPages) {
        _fetchPageLines(p);
      }
      for (final p in _nextPages) {
        _fetchPageLines(p);
      }

      // Scroll to resumed line or initial target
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToResumedPosition(initialLine, initialPage);
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToResumedPosition(int targetLine, int targetPage) {
    if (!mounted) return;
    final blockKey = _blockKeys[targetLine];
    final blockCtx = blockKey?.currentContext;
    if (blockCtx != null) {
      Scrollable.ensureVisible(
        blockCtx,
        duration: const Duration(milliseconds: 350),
        alignment: 0.05,
      );
      return;
    }

    final pageKey = _pageKeys[targetPage];
    final pageCtx = pageKey?.currentContext;
    if (pageCtx != null) {
      Scrollable.ensureVisible(
        pageCtx,
        duration: const Duration(milliseconds: 350),
        alignment: 0.0,
      );
    }
  }

  Future<List<BookLine>> _fetchPageLines(int page) async {
    if (_pageCache.containsKey(page)) return _pageCache[page]!;
    final lines = await _bookService.getPageLines(widget.bookId, page);
    final highlights = await _bookService.getHighlightsForPage(widget.bookId, page);
    _pageCache[page] = lines;
    _highlightCache[page] = highlights;
    if (mounted) setState(() {});
    return lines;
  }

  void _turnSpread(int delta) {
    if (_book == null) return;
    final totalPages = _book!.totalPages;
    final newLeft = (_spreadLeftPage + delta).clamp(1, totalPages);
    if (newLeft != _spreadLeftPage) {
      setState(() {
        _spreadLeftPage = newLeft;
        _currentPage = newLeft;
      });
      _fetchPageLines(newLeft);
      if (newLeft + 1 <= totalPages) _fetchPageLines(newLeft + 1);

      // Track active line on the spread
      final lines = _pageCache[newLeft];
      final firstLine = (lines != null && lines.isNotEmpty) ? lines.first.lineNumber : 1;
      final percent = (firstLine / (_book!.totalLines > 0 ? _book!.totalLines : 1)).clamp(0.0, 1.0);
      _markProgressChanged(newLeft, firstLine, percent);
    }
  }

  Future<void> _jumpToPage(int page) async {
    if (_book == null) return;
    final targetPage = page.clamp(1, _book!.totalPages);

    final screen = ScreenClass.of(context);
    if (screen == ScreenClass.expanded) {
      final newLeft = (targetPage % 2 == 0)
          ? (targetPage - 1).clamp(1, _book!.totalPages)
          : targetPage;
      setState(() {
        _spreadLeftPage = newLeft;
        _currentPage = newLeft;
      });
      await _fetchPageLines(newLeft);
      if (newLeft + 1 <= _book!.totalPages) await _fetchPageLines(newLeft + 1);
      final lines = _pageCache[newLeft];
      final firstLine = (lines != null && lines.isNotEmpty) ? lines.first.lineNumber : 1;
      final percent = (firstLine / (_book!.totalLines > 0 ? _book!.totalLines : 1)).clamp(0.0, 1.0);
      _markProgressChanged(newLeft, firstLine, percent);
      return;
    }

    final key = _pageKeys[targetPage];
    final ctx = key?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
      setState(() => _currentPage = targetPage);
      final lines = _pageCache[targetPage];
      final firstLine = (lines != null && lines.isNotEmpty) ? lines.first.lineNumber : 1;
      final percent = (firstLine / (_book!.totalLines > 0 ? _book!.totalLines : 1)).clamp(0.0, 1.0);
      _markProgressChanged(targetPage, firstLine, percent);
      return;
    }

    setState(() {
      _centerPage = targetPage;
      _centerKey = UniqueKey();
      _prevPages.clear();
      if (targetPage > 1) {
        _prevPages.add(targetPage - 1);
        if (targetPage > 2) _prevPages.add(targetPage - 2);
      }
      _nextPages.clear();
      _nextPages.add(targetPage);
      if (targetPage < _book!.totalPages) {
        _nextPages.add(targetPage + 1);
        if (targetPage + 1 < _book!.totalPages) _nextPages.add(targetPage + 2);
      }
      _currentPage = targetPage;
    });

    await _fetchPageLines(targetPage);
    for (final p in _prevPages) {
      _fetchPageLines(p);
    }
    for (final p in _nextPages) {
      _fetchPageLines(p);
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    final lines = _pageCache[targetPage];
    final firstLine = (lines != null && lines.isNotEmpty) ? lines.first.lineNumber : 1;
    final percent = (firstLine / (_book!.totalLines > 0 ? _book!.totalLines : 1)).clamp(0.0, 1.0);
    _markProgressChanged(targetPage, firstLine, percent);
  }

  String _currentChapterTitle() {
    for (final ch in _chapters) {
      if (_currentPage >= ch.startPage && _currentPage <= ch.endPage) {
        return ch.chapterTitle;
      }
    }
    return '';
  }

  void _openToc(bool isExpanded) {
    if (_book == null) return;
    BookTocSheet.show(
      context,
      bookTitle: _book!.title,
      chapters: _chapters,
      currentPage: _currentPage,
      showPageNumbers: isExpanded,
      onSelectPage: _jumpToPage,
    );
  }

  void _openHighlights() {
    if (_book == null) return;
    BookHighlightsSheet.show(
      context,
      bookId: _book!.id,
      bookTitle: _book!.title,
      onSelectPage: _jumpToPage,
    );
  }

  // --- Reading Theme Colors ---
  Color _readerBackground(BuildContext context) {
    final tokens = context.tokens;
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFFFAF9F6);
      case ReaderThemeMode.sepia:
        return const Color(0xFFFBF0D9);
      case ReaderThemeMode.dark:
        return const Color(0xFF1E212B);
      case ReaderThemeMode.amoled:
        return const Color(0xFF000000);
      case ReaderThemeMode.system:
        return tokens.background;
    }
  }

  Color _readerTextColor(BuildContext context) {
    final tokens = context.tokens;
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFF1A1A1A);
      case ReaderThemeMode.sepia:
        return const Color(0xFF3B2F2F);
      case ReaderThemeMode.dark:
        return const Color(0xFFE6EDF3);
      case ReaderThemeMode.amoled:
        return const Color(0xFFFFFFFF);
      case ReaderThemeMode.system:
        return tokens.onSurface;
    }
  }

  void _showAppearanceSheet(BuildContext context) {
    final tokens = context.tokens;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.surfaceBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Reading Appearance',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Theme selector
                    Text('Theme', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildThemeChip(ctx, 'Paper', ReaderThemeMode.paper, const Color(0xFFFAF9F6), const Color(0xFF1A1A1A), setModalState),
                        const SizedBox(width: 8),
                        _buildThemeChip(ctx, 'Sepia', ReaderThemeMode.sepia, const Color(0xFFFBF0D9), const Color(0xFF3B2F2F), setModalState),
                        const SizedBox(width: 8),
                        _buildThemeChip(ctx, 'Dark', ReaderThemeMode.dark, const Color(0xFF1E212B), const Color(0xFFE6EDF3), setModalState),
                        const SizedBox(width: 8),
                        _buildThemeChip(ctx, 'AMOLED', ReaderThemeMode.amoled, const Color(0xFF000000), const Color(0xFFFFFFFF), setModalState),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Font family
                    Text('Font Family', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _useSerifFont ? tokens.accent.withValues(alpha: 0.15) : null,
                              side: BorderSide(color: _useSerifFont ? tokens.accent : tokens.surfaceBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              setModalState(() => _useSerifFont = true);
                              setState(() => _useSerifFont = true);
                            },
                            child: Text(
                              'Serif (Book)',
                              style: TextStyle(
                                fontFamily: 'serif',
                                color: _useSerifFont ? tokens.accent : tokens.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: !_useSerifFont ? tokens.accent.withValues(alpha: 0.15) : null,
                              side: BorderSide(color: !_useSerifFont ? tokens.accent : tokens.surfaceBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              setModalState(() => _useSerifFont = false);
                              setState(() => _useSerifFont = false);
                            },
                            child: Text(
                              'Sans-Serif (Modern)',
                              style: TextStyle(
                                color: !_useSerifFont ? tokens.accent : tokens.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Font size slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Font Size', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
                        Text('${_fontSize.toInt()} pt', style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _fontSize,
                      min: 14.0,
                      max: 26.0,
                      divisions: 12,
                      activeColor: tokens.accent,
                      onChanged: (val) {
                        setModalState(() => _fontSize = val);
                        setState(() => _fontSize = val);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemeChip(
    BuildContext context,
    String label,
    ReaderThemeMode mode,
    Color bg,
    Color text,
    StateSetter setModalState,
  ) {
    final tokens = context.tokens;
    final isSelected = _themeMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setModalState(() => _themeMode = mode);
          setState(() => _themeMode = mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.surfaceBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  int _currentChapterIndex() {
    for (final ch in _chapters) {
      if (_currentPage >= ch.startPage && _currentPage <= ch.endPage) {
        return ch.chapterIndex;
      }
    }
    return 1;
  }

  // --- Highlight Creation ---
  Future<void> _createHighlight(String text, int startChar, {int color = 0}) async {
    if (_book == null || text.trim().isEmpty) return;

    final highlight = BookHighlight(
      id: '${_book!.id}_${_currentPage}_${DateTime.now().millisecondsSinceEpoch}',
      bookId: _book!.id,
      chapterIndex: _currentChapterIndex(),
      pageNumber: _currentPage,
      startChar: startChar,
      endChar: startChar + text.length,
      text: text,
      color: color,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _bookService.saveHighlight(highlight);
    _highlightCache[_currentPage]?.add(highlight);
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Highlight saved'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // --- Inline Scripture Link & Text Rendering ---
  List<InlineSpan> _buildFormattedParagraphs(
    String pageText,
    Color textColor,
    AppTokens tokens,
  ) {
    final pageHighlights = _highlightCache[_currentPage] ?? const [];
    final matches = ScriptureRefParser.scriptureRegex.allMatches(pageText).toList();

    if (matches.isEmpty) {
      final spans = <InlineSpan>[];
      _appendSpansWithHighlights(spans, pageText, textColor, pageHighlights);
      return spans;
    }

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        final chunk = pageText.substring(lastMatchEnd, match.start);
        _appendSpansWithHighlights(spans, chunk, textColor, pageHighlights);
      }

      final refText = match.group(0)!;
      final parsed = ScriptureRefParser.parse(refText);

      spans.add(TextSpan(
        text: refText,
        style: TextStyle(
          color: tokens.accent,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          decorationColor: tokens.accent.withValues(alpha: 0.6),
          fontSize: _fontSize,
          height: _lineHeight,
          fontFamily: _useSerifFont ? 'serif' : null,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
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
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < pageText.length) {
      final chunk = pageText.substring(lastMatchEnd);
      _appendSpansWithHighlights(spans, chunk, textColor, pageHighlights);
    }

    return spans;
  }

  void _appendSpansWithHighlights(
    List<InlineSpan> spans,
    String text,
    Color textColor,
    List<BookHighlight> highlights,
  ) {
    if (highlights.isEmpty) {
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: _fontSize,
          height: _lineHeight,
          fontFamily: _useSerifFont ? 'serif' : null,
        ),
      ));
      return;
    }

    int current = 0;
    while (current < text.length) {
      int nextMatchStart = text.length;
      BookHighlight? matchedHighlight;

      for (final h in highlights) {
        if (h.text.isEmpty) continue;
        final idx = text.indexOf(h.text, current);
        if (idx != -1 && idx < nextMatchStart) {
          nextMatchStart = idx;
          matchedHighlight = h;
        }
      }

      if (matchedHighlight != null && nextMatchStart < text.length) {
        if (nextMatchStart > current) {
          spans.add(TextSpan(
            text: text.substring(current, nextMatchStart),
            style: TextStyle(
              color: textColor,
              fontSize: _fontSize,
              height: _lineHeight,
              fontFamily: _useSerifFont ? 'serif' : null,
            ),
          ));
        }

        spans.add(TextSpan(
          text: matchedHighlight.text,
          style: TextStyle(
            color: textColor,
            backgroundColor: Colors.amber.withValues(alpha: 0.35),
            fontSize: _fontSize,
            height: _lineHeight,
            fontFamily: _useSerifFont ? 'serif' : null,
          ),
        ));

        current = nextMatchStart + matchedHighlight.text.length;
      } else {
        spans.add(TextSpan(
          text: text.substring(current),
          style: TextStyle(
            color: textColor,
            fontSize: _fontSize,
            height: _lineHeight,
            fontFamily: _useSerifFont ? 'serif' : null,
          ),
        ));
        break;
      }
    }
  }

  // --- Context Menu Toolbar for Selection ---
  Widget _buildSelectionToolbar(BuildContext context, SelectableRegionState selectableRegionState) {
    String selectedText = '';
    try {
      final dynamic dyn = selectableRegionState;
      final dynamic content = dyn.getSelectedContent();
      if (content != null && content.plainText != null && (content.plainText as String).trim().isNotEmpty) {
        selectedText = (content.plainText as String).trim();
      }
    } catch (_) {}

    if (selectedText.isEmpty) {
      final val = selectableRegionState.textEditingValue;
      selectedText = (val.selection.isValid && !val.selection.isCollapsed)
          ? val.selection.textInside(val.text).trim()
          : val.text.trim();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: [
        ContextMenuButtonItem(
          label: 'Highlight',
          onPressed: () {
            selectableRegionState.hideToolbar();
            if (selectedText.isNotEmpty) {
              _createHighlight(selectedText, 0);
            }
          },
        ),
        ContextMenuButtonItem(
          label: 'Define',
          onPressed: () {
            selectableRegionState.hideToolbar();
            final words = selectedText
                .split(RegExp(r'\s+'))
                .map((w) => w.replaceAll(RegExp(r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]'''), ''))
                .where((w) => w.isNotEmpty)
                .toList();
            final lookupWord = words.isNotEmpty ? words.first : selectedText;
            InlineDictionaryPopover.show(context, word: lookupWord);
          },
        ),
        ContextMenuButtonItem(
          label: 'Copy',
          onPressed: () {
            selectableRegionState.copySelection(SelectionChangedCause.toolbar);
          },
        ),
      ],
    );
  }

  // --- Single Column Continuous Infinite Scroll (Mobile screens: NO page numbers) ---
  Widget _buildInfiniteScrollView(AppTokens tokens) {
    final textColor = _readerTextColor(context);

    return GestureDetector(
      onTap: () => setState(() => _showChrome = !_showChrome),
      behavior: HitTestBehavior.opaque,
      child: SelectionArea(
        contextMenuBuilder: (context, state) => _buildSelectionToolbar(context, state),
        child: CustomScrollView(
          controller: _scrollController,
          center: _centerKey,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Upward infinite scroll (previous pages)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final pageNum = _prevPages[index];
                    return _buildPageSection(pageNum, tokens, textColor);
                  },
                  childCount: _prevPages.length,
                ),
              ),
            ),

            // Downward infinite scroll (center and subsequent pages)
            SliverPadding(
              key: _centerKey,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final pageNum = _nextPages[index];
                    return _buildPageSection(pageNum, tokens, textColor);
                  },
                  childCount: _nextPages.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageSection(int pageNum, AppTokens tokens, Color textColor) {
    final lines = _pageCache[pageNum];

    if (lines == null) {
      _fetchPageLines(pageNum);
      return Container(
        key: _pageKeys[pageNum] ??= GlobalKey(),
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
          ),
        ),
      );
    }

    final blocks = BookParagraphGrouper.groupLines(lines);

    return Container(
      key: _pageKeys[pageNum] ??= GlobalKey(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // On mobile screens, NO page numbers are rendered
          if (pageNum > 1) const SizedBox(height: 16),
          ...blocks.map((b) => _buildBlockWidget(b, pageNum, textColor, tokens)),
        ],
      ),
    );
  }

  // --- Dual-Page Spread View (Tablets / Desktop >= 840px: HAS page numbers) ---
  Widget _buildDualPageSpreadView(AppTokens tokens) {
    final textColor = _readerTextColor(context);
    final totalPages = _book?.totalPages ?? 1;
    final leftPage = _spreadLeftPage;
    final rightPage = leftPage + 1 <= totalPages ? leftPage + 1 : null;

    return GestureDetector(
      onTap: () => setState(() => _showChrome = !_showChrome),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left page navigation chevron
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 36),
              color: leftPage > 1 ? tokens.onSurface : tokens.onSurfaceDisabled.withValues(alpha: 0.3),
              onPressed: leftPage > 1 ? () => _turnSpread(-2) : null,
              tooltip: 'Previous pages',
            ),

            // Left Page Column
            Expanded(
              child: _buildPageColumnWithNumber(
                leftPage,
                tokens,
                textColor,
                isRightPage: false,
              ),
            ),

            // Center Book Spine
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              color: tokens.surfaceBorder.withValues(alpha: 0.6),
            ),

            // Right Page Column
            Expanded(
              child: rightPage != null
                  ? _buildPageColumnWithNumber(
                      rightPage,
                      tokens,
                      textColor,
                      isRightPage: true,
                    )
                  : Center(
                      child: Text(
                        'End of Book',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
            ),

            // Right page navigation chevron
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 36),
              color: rightPage != null && rightPage < totalPages
                  ? tokens.onSurface
                  : tokens.onSurfaceDisabled.withValues(alpha: 0.3),
              onPressed: rightPage != null && rightPage < totalPages ? () => _turnSpread(2) : null,
              tooltip: 'Next pages',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageColumnWithNumber(
    int pageNum,
    AppTokens tokens,
    Color textColor, {
    required bool isRightPage,
  }) {
    final lines = _pageCache[pageNum];
    if (lines == null) {
      _fetchPageLines(pageNum);
      return const Center(child: CircularProgressIndicator());
    }

    final blocks = BookParagraphGrouper.groupLines(lines);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SelectionArea(
              contextMenuBuilder: (context, state) => _buildSelectionToolbar(context, state),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: blocks.map((b) => _buildBlockWidget(b, pageNum, textColor, tokens)).toList(),
              ),
            ),
          ),
        ),
        // Dual page screens explicitly show page numbers at the bottom
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          alignment: isRightPage ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            'Page $pageNum',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // --- Block Widget Renderer ---
  Widget _buildBlockWidget(
    BookRenderBlock block,
    int pageNum,
    Color textColor,
    AppTokens tokens,
  ) {
    final isHighlighted = widget.highlightStartLine != null &&
        widget.highlightEndLine != null &&
        block.startLine <= widget.highlightEndLine! &&
        block.endLine >= widget.highlightStartLine!;

    Widget content;

    switch (block.type) {
      case 'chapter_header':
        final chapBadge = block.badge ?? '';
        final chapTitle = block.title ?? block.text;

        content = Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 24, bottom: 20),
          padding: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: tokens.accent.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chapBadge.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    chapBadge.toUpperCase(),
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                chapTitle,
                style: TextStyle(
                  color: textColor,
                  fontSize: (_fontSize + 6).clamp(18.0, 32.0),
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                  fontFamily: _useSerifFont ? 'serif' : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 2.5,
                width: 48,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
        break;

      case 'h2':
        content = Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Text(
            block.text,
            style: TextStyle(
              color: tokens.accent,
              fontSize: (_fontSize + 3.0).clamp(16.0, 26.0),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              fontFamily: _useSerifFont ? 'serif' : null,
            ),
          ),
        );
        break;

      case 'h3':
        content = Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            block.text,
            style: TextStyle(
              color: tokens.accent,
              fontSize: (_fontSize + 1.5).clamp(14.0, 22.0),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              fontFamily: _useSerifFont ? 'serif' : null,
            ),
          ),
        );
        break;

      case 'blockquote':
        content = Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? tokens.accent.withValues(alpha: 0.14)
                : tokens.surfaceVariant.withValues(alpha: 0.45),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
            border: Border(
              left: BorderSide(color: tokens.accent, width: 3.5),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: _buildFormattedParagraphs(block.text, textColor, tokens),
            ),
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: _fontSize,
              height: _lineHeight,
              fontFamily: _useSerifFont ? 'serif' : null,
            ),
          ),
        );
        break;

      case 'p':
      default:
        Widget paragraph = Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(
            TextSpan(
              children: _buildFormattedParagraphs(block.text, textColor, tokens),
            ),
            textAlign: TextAlign.justify,
          ),
        );

        if (isHighlighted) {
          paragraph = Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: tokens.accent, width: 3)),
            ),
            child: Text.rich(
              TextSpan(
                children: _buildFormattedParagraphs(block.text, textColor, tokens),
              ),
              textAlign: TextAlign.justify,
            ),
          );
        }

        content = paragraph;
        break;
    }

    return KeyedSubtree(
      key: _blockKeys[block.startLine] ??= GlobalKey(),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bgColor = _readerBackground(context);
    final totalPages = _book?.totalPages ?? 1;
    final screen = ScreenClass.of(context);
    final isDualPage = screen == ScreenClass.expanded;
    final rightPage = _spreadLeftPage + 1 <= totalPages ? _spreadLeftPage + 1 : null;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _showChrome
          ? AppBar(
              backgroundColor: bgColor.withValues(alpha: 0.96),
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _book?.title ?? 'Book Reader',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _readerTextColor(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (isDualPage)
                    Text(
                      _currentChapterTitle().isNotEmpty
                          ? '${_currentChapterTitle()} • Pages $_spreadLeftPage–${rightPage ?? _spreadLeftPage} of $totalPages'
                          : 'Pages $_spreadLeftPage–${rightPage ?? _spreadLeftPage} of $totalPages',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                    )
                  else if (_currentChapterTitle().isNotEmpty)
                    Text(
                      _currentChapterTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, color: tokens.accent, size: 22),
                  tooltip: 'Highlights & Notes',
                  onPressed: _openHighlights,
                ),
                IconButton(
                  icon: Icon(Icons.text_fields_rounded, color: tokens.onSurfaceMuted, size: 21),
                  tooltip: 'Reading settings',
                  onPressed: () => _showAppearanceSheet(context),
                ),
                IconButton(
                  icon: Icon(Icons.list_alt_rounded, color: tokens.onSurfaceMuted, size: 21),
                  tooltip: 'Table of contents',
                  onPressed: () => _openToc(isDualPage),
                ),
              ],
            )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: tokens.accent))
          : _book == null
              ? Center(
                  child: Text('Book not found', style: TextStyle(color: tokens.onSurfaceMuted)),
                )
              : isDualPage
                  ? _buildDualPageSpreadView(tokens)
                  : MaxWidthBox(
                      maxWidth: 760,
                      child: _buildInfiniteScrollView(tokens),
                    ),
      bottomNavigationBar: _showChrome && _book != null
          ? Container(
              color: bgColor.withValues(alpha: 0.96),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDualPage) ...[
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            color: _spreadLeftPage > 1 ? tokens.onSurface : tokens.onSurfaceDisabled,
                            onPressed: _spreadLeftPage > 1 ? () => _turnSpread(-2) : null,
                          ),
                          Expanded(
                            child: Slider(
                              value: _spreadLeftPage.toDouble(),
                              min: 1.0,
                              max: totalPages.toDouble(),
                              activeColor: tokens.accent,
                              onChanged: (val) => _jumpToPage(val.toInt()),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            color: rightPage != null && rightPage < totalPages
                                ? tokens.onSurface
                                : tokens.onSurfaceDisabled,
                            onPressed: rightPage != null && rightPage < totalPages ? () => _turnSpread(2) : null,
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Pages $_spreadLeftPage–${rightPage ?? _spreadLeftPage} of $totalPages • ${(_lastPercent * 100).toInt()}% complete',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _lastPercent,
                              min: 0.0,
                              max: 1.0,
                              activeColor: tokens.accent,
                              onChanged: (val) {
                                final targetPage = ((val * totalPages).round()).clamp(1, totalPages);
                                _jumpToPage(targetPage);
                              },
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _currentChapterTitle().isNotEmpty
                              ? '${_currentChapterTitle()} • ${(_lastPercent * 100).toInt()}% complete'
                              : '${(_lastPercent * 100).toInt()}% complete',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
