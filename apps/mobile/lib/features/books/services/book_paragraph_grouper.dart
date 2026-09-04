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
