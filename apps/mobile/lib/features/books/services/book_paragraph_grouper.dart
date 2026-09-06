import 'package:mobile/features/books/models/book_line.dart';

class BookRenderBlock {
  final String type; // 'chapter_header', 'h2', 'h3', 'blockquote', 'p'
  final String text;
  final String? badge; // For chapter badge like "CHAPTER 1"
  final String? title; // For chapter title like "Some Foundational Principles"
  final int startLine;
  final int endLine;

  const BookRenderBlock({
    required this.type,
    required this.text,
    this.badge,
    this.title,
    required this.startLine,
    required this.endLine,
  });
}

/// Groups raw [BookLine] database records into coherent structural blocks
/// (paragraphs, headings, blockquotes, chapter headers) so that only genuine
/// paragraphs receive paragraph breaks and spacing rather than every single
/// line record in the database.
class BookParagraphGrouper {
  static final _termRegex = RegExp(r'[.!?\”\"' "'" r'’]$');
  static final _quoteTermRegex = RegExp(r'[\”\"' "'" r'’]$');
  static final _punctRegex = RegExp(r'[.!?,:;\”\"' "'" r'’]$');
  static final _leadWordRegex = RegExp(r'^(and|but|for|or|the|in|to)\s', caseSensitive: false);
  static final _numberedHeadingRegex = RegExp(r'^(?:\d+\.|\(I{1,3}|IV|V?I{0,3}\)|[IVX]+\.)\s+[A-Z]');
  static final _chapRegex = RegExp(r'^Chapter\s+\d+', caseSensitive: false);
  static final _chapMatchRegex = RegExp(r'^(Chapter\s+\d+|[A-Z\s]+)\s*(.*)$', caseSensitive: false);
  static final _chapStripRegex = RegExp(r'^Chapter\s+\d+\s*', caseSensitive: false);

  /// Classifies a single [line] into the block type its own content type group
  /// opens in continuous-scroll mode, where every source line is rendered
  /// independently. Only explicit markers are honored: structure-preserving
  /// heuristics like the numbered/short-title detection in [groupLines] are
  /// context-sensitive and would mis-classify plain paragraph lines as headings
  /// when applied per line.
  static BookRenderBlock blockFromLine(BookLine line) {
    final text = line.text.trim();

    if (line.contentType == 'img') {
      return BookRenderBlock(
        type: 'img',
        text: text,
        startLine: line.lineNumber,
        endLine: line.lineNumber,
      );
    }

    final isChapHeader = line.contentType == 'chapter_header' ||
        (line.contentType == 'p' && _chapRegex.hasMatch(text) && text.length < 80);
  if (isChapHeader) {
    final match = _chapMatchRegex.firstMatch(text);
    final badge = match?.group(1)?.trim();
    final rawTitle = match?.group(2)?.trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : text;
    return BookRenderBlock(
      type: 'chapter_header',
      text: text,
      badge: badge,
      title: title,
      startLine: line.lineNumber,
      endLine: line.lineNumber,
    );
  }

  final type = line.contentType;
  if (type == 'h2' || type == 'h3' || type == 'blockquote') {
    return BookRenderBlock(
      type: type,
      text: text,
      startLine: line.lineNumber,
      endLine: line.lineNumber,
    );
  }

  return BookRenderBlock(
    type: 'p',
    text: text,
    startLine: line.lineNumber,
    endLine: line.lineNumber,
  );
}

/// Whether a visual paragraph break should separate consecutive source lines
/// [prev] and [next] in a continuous scroll. Applies the same terminal/short
/// and next-is-special heuristics used to close paragraphs in [groupLines].
static bool isParagraphBreakBetween(BookLine? prev, BookLine? next) {
  if (prev == null) return false;
  if (prev.contentType != 'p' || (next != null && next.contentType != 'p')) {
    return true;
  }
  if (next == null) return true;
  final text = prev.text.trim();
  if (text.isEmpty) return true;
  if (!_termRegex.hasMatch(text)) return false;

  final isShortLine = text.length < 60;
  if (isShortLine) return true;
  if (_quoteTermRegex.hasMatch(text)) return true;

  final nextText = next.text.trim();
  return nextText.isEmpty ||
      next.contentType != 'p' ||
      _chapRegex.hasMatch(nextText) ||
      _numberedHeadingRegex.hasMatch(nextText) ||
      (nextText.length <= 45 &&
          !_punctRegex.hasMatch(nextText) &&
          !nextText.contains(','));
}

static List<BookRenderBlock> groupLines(List<BookLine> lines) {
    final blocks = <BookRenderBlock>[];
    final currentParagraph = <String>[];
    int startLine = 1;
    int endLine = 1;

    void flushParagraph() {
      if (currentParagraph.isNotEmpty) {
        blocks.add(BookRenderBlock(
          type: 'p',
          text: currentParagraph.join(' '),
          startLine: startLine,
          endLine: endLine,
        ));
        currentParagraph.clear();
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final text = line.text.trim();
      if (text.isEmpty) continue;

      // 0. Image page (scanned book) — standalone full-page image, never
      // accumulated into a text paragraph.
      if (line.contentType == 'img') {
        flushParagraph();
        blocks.add(BookRenderBlock(
          type: 'img',
          text: text,
          startLine: line.lineNumber,
          endLine: line.lineNumber,
        ));
        continue;
      }

      // 1. Chapter Header
      final isChapHeader = line.contentType == 'chapter_header' ||
          (line.contentType == 'p' && _chapRegex.hasMatch(text) && text.length < 80);

      if (isChapHeader) {
        flushParagraph();
        final match = _chapMatchRegex.firstMatch(text);
        final badge = match?.group(1)?.trim();
        final rawTitle = match?.group(2)?.trim();
        final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : text;

        blocks.add(BookRenderBlock(
          type: 'chapter_header',
          text: text,
          badge: badge,
          title: title,
          startLine: line.lineNumber,
          endLine: line.lineNumber,
        ));

        // Deduplicate immediately following redundant heading line
        if (i + 1 < lines.length && (lines[i + 1].contentType == 'h3' || lines[i + 1].contentType == 'p')) {
          final nextT = lines[i + 1].text.trim();
          if (nextT == text ||
              nextT == title ||
              nextT.replaceFirst(_chapStripRegex, '') == text.replaceFirst(_chapStripRegex, '')) {
            i++;
          }
        }
        continue;
      }

      // 2. Explicit Headings
      if (line.contentType == 'h2' || line.contentType == 'h3') {
        flushParagraph();
        blocks.add(BookRenderBlock(
          type: line.contentType,
          text: text,
          startLine: line.lineNumber,
          endLine: line.lineNumber,
        ));
        continue;
      }

      // 3. Numbered section heading (e.g. "1. ", "I. ", "(I) ")
      if (_numberedHeadingRegex.hasMatch(text) && text.length < 75) {
        flushParagraph();
        blocks.add(BookRenderBlock(
          type: 'h3',
          text: text,
          startLine: line.lineNumber,
          endLine: line.lineNumber,
        ));
        continue;
      }

      // 4. Standalone short section title without ending punctuation
      if (text.length <= 45 &&
          !_punctRegex.hasMatch(text) &&
          !text.contains(',') &&
          !_leadWordRegex.hasMatch(text)) {
        flushParagraph();
        blocks.add(BookRenderBlock(
          type: 'h3',
          text: text,
          startLine: line.lineNumber,
          endLine: line.lineNumber,
        ));
        continue;
      }

      // 5. Blockquote
      if (line.contentType == 'blockquote') {
        flushParagraph();
        blocks.add(BookRenderBlock(
          type: 'blockquote',
          text: text,
          startLine: line.lineNumber,
          endLine: line.lineNumber,
        ));
        continue;
      }

      // 6. Accumulate into current paragraph
      if (currentParagraph.isEmpty) {
        startLine = line.lineNumber;
      }
      endLine = line.lineNumber;
      currentParagraph.add(text);

      // Check if this line marks the true end of a paragraph
      final endsWithTerminal = _termRegex.hasMatch(text);
      final isShortLine = text.length < 60;
      final nextLine = i + 1 < lines.length ? lines[i + 1].text.trim() : null;
      final nextIsSpecial = nextLine != null && (
        lines[i + 1].contentType == 'chapter_header' ||
        lines[i + 1].contentType == 'h2' ||
        lines[i + 1].contentType == 'h3' ||
        lines[i + 1].contentType == 'blockquote' ||
        _chapRegex.hasMatch(nextLine) ||
        _numberedHeadingRegex.hasMatch(nextLine) ||
        (nextLine.length <= 45 && !_punctRegex.hasMatch(nextLine) && !nextLine.contains(','))
      );

      if (endsWithTerminal) {
        if (isShortLine || nextIsSpecial || _quoteTermRegex.hasMatch(text)) {
          flushParagraph();
        }
      }
    }

    flushParagraph();
    return blocks;
  }
}
