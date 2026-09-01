import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../dictionary/widgets/inline_dictionary_popover.dart';
import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_highlight.dart';
import '../models/book_line.dart';
import '../services/book_service.dart';
import '../services/scripture_ref_parser.dart';
import '../widgets/book_highlights_sheet.dart';
import '../widgets/book_toc_sheet.dart';
import '../widgets/scripture_verse_popup.dart';

enum ReaderThemeMode { system, paper, sepia, dark, amoled }

/// Kindle-style reading screen featuring:
/// - Smooth page-turning (Kindle swipe / tap page-turn) with full reverse & forward traversal
/// - Natural paragraph typography with font family (Serif/Sans), size, and line-height controls
/// - Multiple reading themes (Paper, Sepia, Slate Dark, AMOLED Black)
/// - Text highlighting with 4 colors, persisted to SQLite
/// - Inline scripture link detection with popover previews
/// - Integrated dictionary lookup on text selection
/// - Persisted reading position restoration on tap
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
  late final PageController _pageController;

  Book? _book;
  List<BookChapter> _chapters = [];
  bool _isLoading = true;
  int _currentPage = 1;
  bool _showChrome = true;

  // Reading appearance settings
  double _fontSize = 17.0;
  final double _lineHeight = 1.65;
  bool _useSerifFont = true;
  ReaderThemeMode _themeMode = ReaderThemeMode.system;

  // In-memory page & highlight cache for instantaneous page flips
  final Map<int, List<BookLine>> _pageCache = {};
  final Map<int, List<BookHighlight>> _highlightCache = {};

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage ?? 1;
    _pageController = PageController(initialPage: _currentPage - 1);
    _loadBook();
  }

  @override
  void dispose() {
    _saveProgress();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadBook() async {
    final book = await _bookService.getBook(widget.bookId);
    final chapters = await _bookService.getChapters(widget.bookId);

    if (book != null) {
      if (mounted) {
        setState(() {
          _book = book;
          _chapters = chapters;
          _isLoading = false;
        });
      }
      // Pre-warm the current and surrounding pages
      await _fetchPageLines(_currentPage);
      if (_currentPage > 1) _fetchPageLines(_currentPage - 1);
      if (_currentPage < book.totalPages) _fetchPageLines(_currentPage + 1);
    } else {
      if (mounted) setState(() => _isLoading = false);
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

  void _onPageChanged(int pageIndex) {
    final newPage = pageIndex + 1;
    setState(() {
      _currentPage = newPage;
    });

    _saveProgress();

    // Pre-cache adjacent pages
    if (_book != null) {
      if (newPage > 1 && !_pageCache.containsKey(newPage - 1)) {
        _fetchPageLines(newPage - 1);
      }
      if (newPage < _book!.totalPages && !_pageCache.containsKey(newPage + 1)) {
        _fetchPageLines(newPage + 1);
      }
    }
  }

  void _jumpToPage(int page) {
    if (_book == null) return;
    final targetPage = page.clamp(1, _book!.totalPages);
    _pageController.jumpToPage(targetPage - 1);
  }

  void _saveProgress() {
    if (_book == null || _book!.totalPages == 0) return;
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
        return Colors.black;
      case ReaderThemeMode.system:
        return tokens.background;
    }
  }

  Color _readerTextColor(BuildContext context) {
    final tokens = context.tokens;
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFF1C1917);
      case ReaderThemeMode.sepia:
        return const Color(0xFF382A1D);
      case ReaderThemeMode.dark:
        return const Color(0xFFE2E4EB);
      case ReaderThemeMode.amoled:
        return const Color(0xFFF3F3F3);
      case ReaderThemeMode.system:
        return tokens.onSurface;
    }
  }

  Color _highlightColor(int colorIndex) {
    switch (colorIndex) {
      case 1:
        return const Color(0x6681C784); // Green
      case 2:
        return const Color(0x6664B5F6); // Blue
      case 3:
        return const Color(0x66F48FB1); // Pink
      case 0:
      default:
        return const Color(0x77FFD54F); // Yellow / Amber
    }
  }

  // --- Highlights & Annotation Actions ---
  Future<void> _createHighlight(String text, int colorIndex) async {
    if (_book == null || text.trim().isEmpty) return;

    final highlight = BookHighlight(
      id: 'hl_${DateTime.now().millisecondsSinceEpoch}',
      bookId: _book!.id,
      chapterIndex: 1,
      pageNumber: _currentPage,
      startChar: 0,
      endChar: text.length,
      text: text.trim(),
      color: colorIndex,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _bookService.saveHighlight(highlight);
    _highlightCache[_currentPage] = await _bookService.getHighlightsForPage(widget.bookId, _currentPage);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Highlight saved'), duration: Duration(seconds: 1)),
      );
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: tokens.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Reading Appearance',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),

                // Theme selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildThemeChip('System', ReaderThemeMode.system, tokens, setModalState),
                    _buildThemeChip('Paper', ReaderThemeMode.paper, tokens, setModalState),
                    _buildThemeChip('Sepia', ReaderThemeMode.sepia, tokens, setModalState),
                    _buildThemeChip('Dark', ReaderThemeMode.dark, tokens, setModalState),
                    _buildThemeChip('AMOLED', ReaderThemeMode.amoled, tokens, setModalState),
                  ],
                ),
                const SizedBox(height: 18),

                // Font family toggle
                Row(
                  children: [
                    Text('Font Family', style: TextStyle(color: tokens.onSurface, fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Serif', style: TextStyle(fontFamily: 'serif'))),
                        ButtonSegment(value: false, label: Text('Sans')),
                      ],
                      selected: {_useSerifFont},
                      onSelectionChanged: (val) {
                        setState(() => _useSerifFont = val.first);
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Font size slider
                Row(
                  children: [
                    Icon(Icons.format_size, size: 18, color: tokens.onSurfaceMuted),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 13.0,
                        max: 26.0,
                        divisions: 13,
                        activeColor: tokens.accent,
                        label: '${_fontSize.toInt()}sp',
                        onChanged: (val) {
                          setState(() => _fontSize = val);
                          setModalState(() {});
                        },
                      ),
                    ),
                    Text('${_fontSize.toInt()}sp', style: TextStyle(color: tokens.onSurface, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeChip(String label, ReaderThemeMode mode, AppTokens tokens, StateSetter setModalState) {
    final isSelected = _themeMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => _themeMode = mode);
        setModalState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accent.withValues(alpha: 0.18) : tokens.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? tokens.accent : tokens.onSurface,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // --- Paragraph and Scripture Parsing ---
  List<InlineSpan> _buildFormattedParagraphs(String pageText, Color textColor, AppTokens tokens) {
    final spans = <InlineSpan>[];
    final regex = ScriptureRefParser.scriptureRegex;
    final pageHighlights = _highlightCache[_currentPage] ?? const [];
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(pageText)) {
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
          fontSize: _fontSize,
          height: _lineHeight,
          fontWeight: FontWeight.w600,
          fontFamily: _useSerifFont ? 'serif' : null,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: tokens.accent,
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
            fontSize: _fontSize,
            height: _lineHeight,
            fontFamily: _useSerifFont ? 'serif' : null,
            backgroundColor: _highlightColor(matchedHighlight.color),
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

  Widget _buildPageView(AppTokens tokens) {
    final totalPages = _book?.totalPages ?? 1;

    return PageView.builder(
      controller: _pageController,
      itemCount: totalPages,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final pageNum = index + 1;
        final lines = _pageCache[pageNum];

        if (lines == null) {
          _fetchPageLines(pageNum);
          return const Center(child: CircularProgressIndicator());
        }

        final textColor = _readerTextColor(context);

        return GestureDetector(
          onTap: () => setState(() => _showChrome = !_showChrome),
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: SelectionArea(
              contextMenuBuilder: (context, selectableRegionState) {
                final val = selectableRegionState.textEditingValue;
                final selectedText = (val.selection.isValid && !val.selection.isCollapsed)
                    ? val.selection.textInside(val.text).trim()
                    : val.text.trim();

                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: selectableRegionState.contextMenuAnchors,
                  buttonItems: [
                    ContextMenuButtonItem(
                      label: 'Highlight',
                      onPressed: () {
                        selectableRegionState.hideToolbar();
                        _createHighlight(selectedText, 0);
                      },
                    ),
                    ContextMenuButtonItem(
                      label: 'Define',
                      onPressed: () {
                        selectableRegionState.hideToolbar();
                        final lookupWord = selectedText.split(RegExp(r'\s+')).length <= 3
                            ? selectedText
                            : selectedText.split(RegExp(r'\s+')).first;
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
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines.map((l) => _buildElementWidget(l, textColor, tokens)).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildElementWidget(BookLine line, Color textColor, AppTokens tokens) {
    final type = line.contentType;
    final text = line.text;

    // 1. Chapter Header
    if (type == 'chapter_header' ||
        (type == 'p' && RegExp(r'^Chapter\s+\d+', caseSensitive: false).hasMatch(text) && text.length < 80)) {
      final match = RegExp(r'^(Chapter\s+\d+|[A-Z\s]+)\s*(.*)$', caseSensitive: false).firstMatch(text);
      final chapBadge = match != null ? match.group(1)?.trim() : null;
      final chapTitle = match != null && (match.group(2)?.trim().isNotEmpty ?? false)
          ? match.group(2)!.trim()
          : text;

      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chapBadge != null && chapBadge.isNotEmpty) ...[
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
    }

    // 2. Major Section Heading (h2)
    if (type == 'h2' ||
        (type == 'p' && RegExp(r'^(?:\d+\.|\([I|V|X]+\))\s+[A-Z]').hasMatch(text) && text.length < 65)) {
      return Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.accent,
            fontSize: (_fontSize + 3.0).clamp(16.0, 26.0),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            fontFamily: _useSerifFont ? 'serif' : null,
          ),
        ),
      );
    }

    // 3. Subheading (h3)
    if (type == 'h3') {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.accent,
            fontSize: (_fontSize + 1.5).clamp(14.0, 22.0),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
            fontFamily: _useSerifFont ? 'serif' : null,
          ),
        ),
      );
    }

    // 4. Blockquote / Callout quote
    if (type == 'blockquote') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: tokens.surfaceVariant.withValues(alpha: 0.45),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
          border: Border(
            left: BorderSide(color: tokens.accent, width: 3.5),
          ),
        ),
        child: Text.rich(
          TextSpan(
            children: _buildFormattedParagraphs(text, textColor, tokens),
          ),
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: _fontSize,
            height: _lineHeight,
            fontFamily: _useSerifFont ? 'serif' : null,
          ),
        ),
      );
    }

    // 5. Standard Paragraph (p)
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text.rich(
        TextSpan(
          children: _buildFormattedParagraphs(text, textColor, tokens),
        ),
        textAlign: TextAlign.justify,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bgColor = _readerBackground(context);
    final totalPages = _book?.totalPages ?? 1;
    final percent = (_currentPage / totalPages).clamp(0.0, 1.0);

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
                  Text(
                    _currentChapterTitle().isNotEmpty
                        ? '${_currentChapterTitle()} • Page $_currentPage of $totalPages'
                        : 'Page $_currentPage of $totalPages',
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
                  onPressed: _openToc,
                ),
              ],
            )
          : null,
      body: MaxWidthBox(
        maxWidth: 760,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: tokens.accent))
            : _book == null
                ? Center(
                    child: Text('Book not found', style: TextStyle(color: tokens.onSurfaceMuted)),
                  )
                : _buildPageView(tokens),
      ),
      bottomNavigationBar: _showChrome && _book != null
          ? Container(
              color: bgColor.withValues(alpha: 0.96),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          color: _currentPage > 1 ? tokens.onSurface : tokens.onSurfaceDisabled,
                          onPressed: _currentPage > 1 ? () => _jumpToPage(_currentPage - 1) : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: _currentPage.toDouble(),
                            min: 1.0,
                            max: totalPages.toDouble(),
                            activeColor: tokens.accent,
                            onChanged: (val) => _jumpToPage(val.toInt()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          color: _currentPage < totalPages ? tokens.onSurface : tokens.onSurfaceDisabled,
                          onPressed: _currentPage < totalPages ? () => _jumpToPage(_currentPage + 1) : null,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Page $_currentPage of $totalPages • ${(percent * 100).toInt()}% complete',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
