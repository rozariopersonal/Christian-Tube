import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/widgets/verse_text.dart';
import 'package:mobile/features/books/widgets/reader_selection_toolbar.dart';
import 'package:mobile/features/dictionary/widgets/glossary_entry_sheet.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/ui/double_tap_dictionary_area.dart';

void main() {
  testWidgets('VerseText opens GlossaryEntrySheet on double-tap of a word',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: Scaffold(
          body: VerseText(
            verse: BibleVerse(number: 16, text: 'Grace abounds'),
            appearance: ReaderAppearance(),
            bookNumber: 43,
            chapter: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target =
        tester.getTopLeft(find.byType(RichText).first) + const Offset(60, 10);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GlossaryEntrySheet), findsOneWidget);
  });

  testWidgets('DoubleTapDictionaryArea opens GlossaryEntrySheet on double-tap and toolbar omits Define',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: Scaffold(
          body: DoubleTapDictionaryArea(
            contextMenuBuilder: (context, state) => buildReaderSelectionToolbar(
              context,
              state,
              1,
              onHighlight: (_, __) {},
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Salvation belongs to the Lord'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final wordPos = tester.getTopLeft(find.text('Salvation belongs to the Lord')) +
        const Offset(24, 10);
    await tester.tapAt(wordPos);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(wordPos);
    await tester.pumpAndSettle();

    expect(find.byType(GlossaryEntrySheet), findsOneWidget);
    expect(find.byTooltip('Define'), findsNothing);
  });
}
