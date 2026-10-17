import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/widgets/verse_text.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

void main() {
  testWidgets('VerseText preserves whitespace between words and plain text matching', (tester) async {
    final verse = BibleVerse(
      number: 16,
      text: 'For God so loved the world, that he gave his only begotten Son.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
        home: Scaffold(
          body: VerseText(
            verse: verse,
            appearance: ReaderAppearance(),
            isSelected: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('For God so loved the world'), findsOneWidget);
    expect(find.textContaining('God so loved'), findsOneWidget);
  });
}

