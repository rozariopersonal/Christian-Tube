import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_line.dart';
import '../services/book_service.dart';
import '../widgets/book_toc_sheet.dart';

/// Immersive book reading screen with pagination, deep-link line highlighting,
/// TOC navigation, and auto-persisted reading progress.
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

class _BookReaderScreenState extends State<BookReaderScreen> {
  final BookService _bookService = BookService.instance;
  late final ScrollController _scrollController;

  Book? _book;
  List<BookChapter> _chapters = [];
  List<BookLine> _lines = [];
  bool _isLoading = true;
  int _currentPage = 1;
  double _fontSize = 15.5;
  bool _showLineNumbers = false;
  final GlobalKey _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentPage = widget.initialPage ?? 1;
    _loadBookData();
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBookData() async {
    final book = await _bookService.getBook(widget.bookId);
    final chapters = await _bookService.getChapters(widget.bookId);

    if (book != null) {
      // Load initial buffer of lines (e.g. initialPage - 1 to initialPage + 5)
      final startPage = (_currentPage - 1).clamp(1, book.totalPages);
      final endPage = (_currentPage + 6).clamp(1, book.totalPages);
      final lines = await _bookService.getPageRangeLines(widget.bookId, startPage, endPage);

      if (mounted) {
        setState(() {
          _book = book;
          _chapters = chapters;
          _lines = lines;
          _isLoading = false;
        });

        // Auto-scroll to highlighted line if deep-linked
        if (widget.highlightStartLine != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToHighlight();
          });
        }
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToHighlight() {
    if (_highlightKey.currentContext != null) {
      Scrollable.ensureVisible(
        _highlightKey.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        alignment: 0.3,
      );
    }
  }

  Future<void> _jumpToPage(int page) async {
    if (_book == null) return;
    final targetPage = page.clamp(1, _book!.totalPages);
    setState(() {
      _currentPage = targetPage;
      _isLoading = true;
    });

    final startPage = (targetPage - 1).clamp(1, _book!.totalPages);
    final endPage = (targetPage + 6).clamp(1, _book!.totalPages);
    final lines = await _bookService.getPageRangeLines(widget.bookId, startPage, endPage);

    if (mounted) {
      setState(() {
        _lines = lines;
        _isLoading = false;
      });
      _scrollController.jumpTo(0);
      _saveProgress();
    }
  }

  void _saveProgress() {
    if (_book == null) return;
    final percent = _currentPage / _book!.totalPages;
    _bookService.saveProgress(_book!.id, _currentPage, 1, percent);
  }

  String _currentChapterTitle() {
    for (final ch in _chapters) {
      if (_currentPage >= ch.startPage && _currentPage <= ch.endPage) {
        return ch.chapterTitle;
      }
    }
    return '';
  }

  void _openToc() {
    if (_book == null) return;
    BookTocSheet.show(
      context,
      bookTitle: _book!.title,
      chapters: _chapters,
      currentPage: _currentPage,
      onSelectPage: _jumpToPage,
    );
  }

  Widget _buildLineItem(BookLine line, AppTokens tokens) {
    final isTargetPage = line.pageNumber == (widget.initialPage ?? 1);
    final isHighlighted = isTargetPage &&
        widget.highlightStartLine != null &&
        line.lineNumber >= widget.highlightStartLine! &&
        line.lineNumber <= (widget.highlightEndLine ?? widget.highlightStartLine!);

    final isFirstHighlight = isTargetPage &&
        widget.highlightStartLine != null &&
        line.lineNumber == widget.highlightStartLine!;

    return Container(
      key: isFirstHighlight ? _highlightKey : null,
      margin: const EdgeInsets.symmetric(vertical: 1.5),
      padding: EdgeInsets.symmetric(
        horizontal: isHighlighted ? 10 : 4,
        vertical: isHighlighted ? 3 : 1,
      ),
      decoration: BoxDecoration(
        color: isHighlighted
            ? tokens.accent.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isHighlighted
            ? Border(left: BorderSide(color: tokens.accent, width: 3))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showLineNumbers)
            SizedBox(
              width: 32,
              child: Text(
                '${line.lineNumber}',
                style: TextStyle(
                  color: tokens.onSurfaceMuted.withValues(alpha: 0.5),
                  fontSize: _fontSize - 3.5,
                  height: 1.5,
                ),
              ),
            ),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(
                color: isHighlighted ? tokens.onSurface : tokens.onSurface.withValues(alpha: 0.92),
                fontSize: _fontSize,
                height: 1.55,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
                letterSpacing: 0.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageDivider(int pageNumber, AppTokens tokens) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.8,
              color: tokens.surfaceBorder.withValues(alpha: 0.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Page $pageNumber of ${_book?.totalPages ?? ""}',
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.8,
              color: tokens.surfaceBorder.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);
    final chapterTitle = _currentChapterTitle();

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _book?.title ?? 'Reading',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            if (chapterTitle.isNotEmpty)
              Text(
                chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showLineNumbers ? Icons.format_list_numbered : Icons.format_list_numbered_outlined,
              color: _showLineNumbers ? tokens.accent : tokens.onSurfaceMuted,
              size: 20,
            ),
            tooltip: 'Toggle line numbers',
            onPressed: () => setState(() => _showLineNumbers = !_showLineNumbers),
          ),
          IconButton(
            icon: Icon(Icons.text_fields_rounded, color: tokens.onSurfaceMuted, size: 20),
            tooltip: 'Font size',
            onPressed: () {
              setState(() {
                _fontSize = _fontSize >= 20.0 ? 14.0 : _fontSize + 2.0;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.list_alt_rounded, color: tokens.accent, size: 22),
            tooltip: 'Table of Contents',
            onPressed: _openToc,
          ),
        ],
      ),
      body: MaxWidthBox(
        maxWidth: 720,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: tokens.accent),
              )
            : _book == null
                ? Center(
                    child: Text('Book not found', style: TextStyle(color: tokens.onSurfaceMuted)),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: screen.isCompact ? 18 : 28,
                        vertical: 16,
                      ),
                      itemCount: _lines.length,
                      itemBuilder: (context, index) {
                        final line = _lines[index];
                        final isFirstLineOfPage = index == 0 || _lines[index - 1].pageNumber != line.pageNumber;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isFirstLineOfPage && line.pageNumber > 1)
                              _buildPageDivider(line.pageNumber, tokens),
                            _buildLineItem(line, tokens),
                          ],
                        );
                      },
                    ),
                  ),
      ),
      bottomNavigationBar: _book != null
          ? Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(top: BorderSide(color: tokens.surfaceBorder, width: 0.8)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: _currentPage > 1 ? tokens.onSurface : tokens.onSurfaceDisabled,
                    onPressed: _currentPage > 1 ? () => _jumpToPage(_currentPage - 1) : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Page $_currentPage of ${_book!.totalPages}',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: _currentPage < _book!.totalPages ? tokens.onSurface : tokens.onSurfaceDisabled,
                    onPressed: _currentPage < _book!.totalPages ? () => _jumpToPage(_currentPage + 1) : null,
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
