import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'formatted_paragraph.dart';

/// Renders a single structural [BookRenderBlock] (paragraph, heading,
/// blockquote, chapter header, scanned-page image) into its widget tree.
///
/// Pure presentational component: it takes everything it needs as constructor
/// parameters and owns no state. Callers provide a key resolver (for the block's
/// GlobalKey used in position tracking), an optional highlight line range, and a
/// recognizer factory for inline scripture references. Scanned-image pages
/// ([BookLine] with `contentType == 'img'`) resolve their URL via
/// [GitHubDataService.bookPageImageUrl] using the caller-supplied [bookId].
class BookBlockWidget extends StatelessWidget {
  final BookRenderBlock block;
  final int pageNum;
  final String bookId;
  final Color textColor;
  final AppTokens tokens;
  final ReaderAppearance appearance;
  final int? highlightStartLine;
  final int? highlightEndLine;
  final List<BookHighlight> highlightCache;
  final Key Function(int pageNum, int startLine) resolveBlockKey;
  final TapGestureRecognizer Function(ParsedScriptureRef? parsed, String refText) makeRecognizer;

  const BookBlockWidget({
    super.key,
    required this.block,
    required this.pageNum,
    required this.bookId,
    required this.textColor,
    required this.tokens,
    required this.appearance,
    required this.highlightStartLine,
    required this.highlightEndLine,
    required this.highlightCache,
    required this.resolveBlockKey,
    required this.makeRecognizer,
  });

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

  Widget _buildPageImage(String fileName) {
    final url = GitHubDataService.bookPageImageUrl(bookId, fileName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (context, _) => SizedBox(
              height: 160,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: tokens.accent,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),
            errorWidget: (context, _, __) => Container(
              height: 120,
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Page image unavailable',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = highlightStartLine != null &&
        highlightEndLine != null &&
        block.startLine <= highlightEndLine! &&
        block.endLine >= highlightStartLine!;

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
        break;

      case 'h2':
        content = Padding(
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
        break;

      case 'h3':
        content = Padding(
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
        break;

      case 'blockquote':
        content = Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? tokens.accent.withValues(alpha: 0.14)
                : appearance.surfaceVariant(tokens).withValues(alpha: 0.7),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
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
        break;

      case 'img':
        content = _buildPageImage(block.text);
        break;

      case 'p':
      default:
        Widget paragraph = Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(
            TextSpan(children: _format(block.text)),
            textAlign: TextAlign.left,
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
              TextSpan(children: _format(block.text)),
              textAlign: TextAlign.left,
            ),
          );
        }

        content = paragraph;
        break;
    }

    return KeyedSubtree(
      key: resolveBlockKey(pageNum, block.startLine),
      child: content,
    );
  }
}
