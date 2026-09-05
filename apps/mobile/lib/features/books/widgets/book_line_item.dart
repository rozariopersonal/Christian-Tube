import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/formatted_paragraph.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// Renders a single source [BookLine] as one scroll item in the continuous
/// reader.
///
/// The line is classified via [BookParagraphGrouper.blockFromLine] and styled
/// per structural type, mirroring the paginated reader's look without
/// multi-line block grouping or per-item [GlobalKey]s. Spacing between
/// consecutive paragraph lines is driven by [paragraphBreakAfter] so logical
/// paragraph gaps survive the line-per-item model.
class BookLineItem extends StatelessWidget {
  const BookLineItem({
    super.key,
    required this.line,
    required this.textColor,
    required this.tokens,
    required this.appearance,
    required this.highlightCache,
    required this.makeRecognizer,
    this.paragraphBreakAfter = false,
  });

  final BookLine line;
  final Color textColor;
  final AppTokens tokens;
  final ReaderAppearance appearance;
  final List<BookHighlight> highlightCache;
  final TapGestureRecognizer Function(
      ParsedScriptureRef? parsed, String refText) makeRecognizer;
  final bool paragraphBreakAfter;

  List<InlineSpan> _format(String text) {
    return FormattedParagraphBuilder.build(
      text,
      textColor,
      tokens,
      appearance,
      highlightCache,
      makeRecognizer: makeRecognizer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final block = BookParagraphGrouper.blockFromLine(line);

    switch (block.type) {
      case 'chapter_header':
        final badge = block.badge ?? '';
        final title = block.title ?? block.text;
        return Container(
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
              if (badge.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    badge.toUpperCase(),
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
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: (appearance.fontSize + 6).clamp(18.0, 32.0),
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                  fontFamily: appearance.useSerifFont ? 'serif' : null,
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

      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Text(
            block.text,
            style: TextStyle(
              color: tokens.accent,
              fontSize: (appearance.fontSize + 3.0).clamp(16.0, 26.0),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              fontFamily: appearance.useSerifFont ? 'serif' : null,
            ),
          ),
        );

      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            block.text,
            style: TextStyle(
              color: tokens.accent,
              fontSize: (appearance.fontSize + 1.5).clamp(14.0, 22.0),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              fontFamily: appearance.useSerifFont ? 'serif' : null,
            ),
          ),
        );

      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: appearance
                .surfaceVariant(tokens)
                .withValues(alpha: 0.7),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(8)),
            border: Border(
              left: BorderSide(color: tokens.accent, width: 3.5),
            ),
          ),
          child: Text.rich(
            TextSpan(children: _format(block.text)),
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: appearance.fontSize,
              height: appearance.lineHeight,
              fontFamily: appearance.useSerifFont ? 'serif' : null,
            ),
          ),
        );

      case 'p':
      default:
        return Padding(
          padding: EdgeInsets.only(bottom: paragraphBreakAfter ? 14 : 4),
          child: Text.rich(
            TextSpan(children: _format(block.text)),
            textAlign: TextAlign.left,
          ),
        );
    }
  }
}