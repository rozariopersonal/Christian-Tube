import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/services/book_reader_appearance.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';

/// Builds the `InlineSpan` tree for a single paragraph of book text.
///
/// Handles:
/// - inline scripture reference detection (rendered as tappable accent spans via
///   a [makeRecognizer] callback)
/// - persisted highlight overlays (tinted background on matching substrings)
///
/// This is pure logic over immutable inputs (text, appearance, highlights); it
/// has no widget lifecycle and is trivially unit-testable.
class FormattedParagraphBuilder {
  const FormattedParagraphBuilder();

  /// Builds a rich text paragraph from [pageText].
  ///
  /// [highlights] are the persisted highlights for the page; when a highlight
  /// substring appears in [pageText] it is tinted. [makeRecognizer] is invoked
  /// for each scripture reference and must return an owned [TapGestureRecognizer].
  static List<InlineSpan> build(
    String pageText,
    Color textColor,
    AppTokens tokens,
    BookReaderAppearance appearance,
    List<BookHighlight> highlights, {
    required TapGestureRecognizer Function(ParsedScriptureRef? parsed, String refText) makeRecognizer,
  }) {
    final matches = ScriptureRefParser.scriptureRegex.allMatches(pageText).toList();

    if (matches.isEmpty) {
      final spans = <InlineSpan>[];
      _appendSpansWithHighlights(spans, pageText, textColor, appearance, highlights);
      return spans;
    }

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        final chunk = pageText.substring(lastMatchEnd, match.start);
        _appendSpansWithHighlights(spans, chunk, textColor, appearance, highlights);
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
          fontSize: appearance.fontSize,
          height: appearance.lineHeight,
          fontFamily: appearance.useSerifFont ? 'serif' : null,
        ),
        recognizer: makeRecognizer(parsed, refText),
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < pageText.length) {
      final chunk = pageText.substring(lastMatchEnd);
      _appendSpansWithHighlights(spans, chunk, textColor, appearance, highlights);
    }

    return spans;
  }

  static void _appendSpansWithHighlights(
    List<InlineSpan> spans,
    String text,
    Color textColor,
    BookReaderAppearance appearance,
    List<BookHighlight> highlights,
  ) {
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: appearance.fontSize,
      height: appearance.lineHeight,
      fontFamily: appearance.useSerifFont ? 'serif' : null,
    );

    if (highlights.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
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
          spans.add(TextSpan(text: text.substring(current, nextMatchStart), style: baseStyle));
        }
        spans.add(TextSpan(
          text: matchedHighlight.text,
          style: baseStyle.copyWith(
            backgroundColor:
                BookReaderAppearance.highlightColorByIndex(matchedHighlight.color).withValues(alpha: 0.38),
          ),
        ));
        current = nextMatchStart + matchedHighlight.text.length;
      } else {
        spans.add(TextSpan(text: text.substring(current), style: baseStyle));
        break;
      }
    }
  }
}
