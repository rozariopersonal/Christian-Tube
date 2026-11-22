import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/services/book_highlight_ranges.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

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
    ReaderAppearance appearance,
    List<BookHighlight> highlights, {
    required TapGestureRecognizer Function(
            ParsedScriptureRef? parsed, String refText)
        makeRecognizer,
    TapGestureRecognizer Function(BookHighlight highlight)?
        makeHighlightRecognizer,
    List<BookLine> sourceLines = const [],
    TextStyle? textStyle,
  }) {
    final fontFamily = ScriptureThemeCatalog.resolveFontFamily(
      appearance.fontFamily,
      appearance.languageCode,
    );
    final textTokens = ScriptureRefParser.tokenize(pageText);
    final spans = <InlineSpan>[];
    final ranges =
        BookHighlightRanges.project(pageText, sourceLines, highlights);
    // Older highlights have no stored location; retain their original display.
    for (final highlight in highlights) {
      if (BookHighlightRanges.lineNumber(highlight) != null ||
          highlight.text.isEmpty) {
        continue;
      }
      var start = pageText.indexOf(highlight.text);
      while (start >= 0) {
        ranges.add((
          start: start,
          end: start + highlight.text.length,
          highlight: highlight
        ));
        start = pageText.indexOf(highlight.text, start + highlight.text.length);
      }
    }
    final baseStyle = textStyle ??
        TextStyle(
          color: textColor,
          fontSize: appearance.fontSize,
          height: appearance.lineHeight,
          fontFamily: fontFamily,
          fontWeight: appearance.fontWeight,
          fontStyle: appearance.fontStyle,
          decoration: appearance.textDecoration,
        );
    var tokenStart = 0;
    for (final token in textTokens) {
      final tokenEnd = tokenStart + token.text.length;
      final boundaries = <int>{tokenStart, tokenEnd};
      for (final range in ranges) {
        if (range.start < tokenEnd && range.end > tokenStart) {
          boundaries.add(range.start.clamp(tokenStart, tokenEnd));
          boundaries.add(range.end.clamp(tokenStart, tokenEnd));
        }
      }
      final cuts = boundaries.toList()..sort();
      for (var i = 0; i + 1 < cuts.length; i++) {
        final start = cuts[i], end = cuts[i + 1];
        BookHighlight? highlight;
        for (final range in ranges) {
          if (range.start <= start && range.end >= end) {
            highlight = range.highlight;
          }
        }
        final reference = token.isReference && token.ref != null;
        var style = reference
            ? baseStyle.copyWith(
                color: tokens.accent,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: tokens.accent.withValues(alpha: 0.6),
              )
            : baseStyle;
        if (highlight != null) {
          style = style.copyWith(
              backgroundColor:
                  ReaderAppearance.highlightColorByIndex(highlight.color)
                      .withValues(alpha: 0.38));
        }
        spans.add(TextSpan(
          text: token.text.substring(start - tokenStart, end - tokenStart),
          style: style,
          recognizer: highlight != null && makeHighlightRecognizer != null
              ? makeHighlightRecognizer(highlight)
              : reference
                  ? makeRecognizer(token.ref, token.text)
                  : null,
        ));
      }
      tokenStart = tokenEnd;
    }
    return spans;
  }
}
