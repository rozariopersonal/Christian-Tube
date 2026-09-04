import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/widgets/formatted_paragraph.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

void main() {
  final appearance = ReaderAppearance();
  const tokens = AppTokens.dark;
  const textColor = Color(0xFFFFFFFF);

  TapGestureRecognizer stubRecognizer(dynamic _, String __) {
    return TapGestureRecognizer();
  }

  group('FormattedParagraphBuilder', () {
    test('renders plain text as a single span with no highlights', () {
      final spans = FormattedParagraphBuilder.build(
        'A simple sentence.',
        textColor,
        tokens,
        appearance,
        const [],
        makeRecognizer: stubRecognizer,
      );
      expect(spans, hasLength(1));
      final span = spans.first as TextSpan;
      expect(span.text, 'A simple sentence.');
      expect(span.style?.backgroundColor, isNull);
    });

    test('splits highlighted substrings into tinted spans', () {
      const lines = [
        BookHighlight(
          id: 'h1',
          bookId: 'b',
          chapterIndex: 1,
          pageNumber: 1,
          startChar: 0,
          endChar: 0,
          text: 'Grace',
          color: 1,
          createdAt: '',
        ),
      ];
      final spans = FormattedParagraphBuilder.build(
        'Grace and peace to you.',
        textColor,
        tokens,
        appearance,
        lines,
        makeRecognizer: stubRecognizer,
      );
      // Expect: "Grace" tinted, then " and peace to you."
      expect(spans.length, inInclusiveRange(2, 3));
      final tinted = spans.whereType<TextSpan>().where((s) => s.style?.backgroundColor != null).toList();
      expect(tinted, isNotEmpty);
      expect(tinted.first.text, 'Grace');
    });

    test('detects scripture references as separate tappable spans', () {
      var recognizerCalls = 0;
      final spans = FormattedParagraphBuilder.build(
        'Read John 3:16 and live.',
        textColor,
        tokens,
        appearance,
        const [],
        makeRecognizer: (parsed, ref) {
          recognizerCalls++;
          return stubRecognizer(parsed, ref);
        },
      );
      expect(recognizerCalls, 1);
      final texts = spans.whereType<TextSpan>().map((s) => s.text).whereType<String>().toList();
      expect(texts.any((t) => t.contains('John 3:16')), isTrue);
    });
  });
}
