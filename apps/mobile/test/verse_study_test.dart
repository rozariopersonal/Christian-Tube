import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/models/cross_reference.dart';
import 'package:mobile/features/bible/models/bible_background_note.dart';
import 'package:mobile/features/bible/widgets/verse_item.dart';
import 'package:mobile/features/bible/widgets/verse_study_badge.dart';
import 'package:mobile/features/bible/widgets/verse_study_inline.dart';
import 'package:mobile/features/bible/screens/verse_study_screen.dart';

void main() {
  final sampleVerse = BibleVerse(
    number: 16,
    text:
        'For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.',
  );

  const sampleCrossRef = CrossReference(
    bookNumber: 62,
    chapter: 4,
    verse: 9,
    endVerse: 10,
    score: 300,
  );

  const sampleNote = BibleBackgroundNote(
    bookNumber: 43,
    chapter: 3,
    verse: 16,
    id: 'v316',
    topic: 'only begotten / one and only',
    quote: 'monogenēs',
    text:
        'The Greek word monogenēs emphasizes uniqueness and special relationship rather than biological generation.',
    source: 'unfoldingWord Cultural Context',
  );

  Widget wrapWithTheme(Widget child, {Size size = const Size(360, 640)}) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [AppTokens.dark],
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Material(child: child),
      ),
    );
  }

  group('VerseStudyBadge & Inline Routing Rules', () {
    testWidgets('Badge displays reference and commentary counts',
        (tester) async {
      bool toggleCalled = false;
      int? openedTab;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyBadge(
            referenceCount: 1,
            commentaryCount: 1,
            isInlineExpanded: false,
            canExpandInline: true,
            onOpenStudyPage: (tab) => openedTab = tab,
            onToggleInline: () => toggleCalled = true,
          ),
        ),
      );

      expect(find.text('1 reference'), findsOneWidget);
      expect(find.text('1 note'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(2));

      await tester.tap(find.text('1 reference'));
      await tester.pump();
      expect(toggleCalled, isTrue);
      expect(openedTab, isNull);
    });

    testWidgets('Multiple items show page indicator and trigger onOpenStudyPage',
        (tester) async {
      int? openedTab;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyBadge(
            referenceCount: 4,
            commentaryCount: 2,
            isInlineExpanded: false,
            canExpandInline: false,
            onOpenStudyPage: (tab) => openedTab = tab,
            onToggleInline: () {},
          ),
        ),
      );

      expect(find.text('4 references'), findsOneWidget);
      expect(find.text('2 commentary'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));

      await tester.tap(find.text('2 commentary'));
      await tester.pump();
      expect(openedTab, 1);
    });
  });

  group('VerseItem with single item inline expansion', () {
    testWidgets('Expands inline when tapped if count <= 1', (tester) async {
      bool isExpanded = false;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return wrapWithTheme(
              VerseItem(
                verse: sampleVerse,
                isSelected: false,
                isHighlighted: false,
                fontSize: 16.0,
                crossReferences: const [sampleCrossRef],
                backgroundNotes: const [sampleNote],
                resolvedTexts: const {
                  '1JN:4:9': 'By this God’s love was revealed in us...',
                },
                isInlineExpanded: isExpanded,
                onToggleInline: () => setState(() => isExpanded = !isExpanded),
                onVerseTap: () {},
              ),
            );
          },
        ),
      );

      // Initially closed
      expect(find.byType(VerseStudyInline), findsNothing);

      // Tap badge to expand
      await tester.tap(find.text('1 reference'));
      await tester.pumpAndSettle();

      // Now expanded inline
      expect(find.byType(VerseStudyInline), findsOneWidget);
      expect(find.text('1JN 4:9-10'), findsOneWidget);
      expect(find.text('only begotten / one and only'), findsOneWidget);
    });
  });

  group('VerseStudyScreen Tabbed UI & Responsiveness', () {
    testWidgets('Renders tabs and allows tab switching without overflow at 320px',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            versionLabel: 'World English Bible',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '1JN:4:9': 'By this God’s love was revealed in us...',
            },
            commentaryNotes: const [sampleNote],
            baseFontSize: 16.0,
            initialTab: 0,
          ),
          size: const Size(320, 600),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Study (JHN 3:16)'), findsOneWidget);
      expect(find.text('References (1)'), findsOneWidget);
      expect(find.text('Commentary (1)'), findsOneWidget);
      expect(find.text('1JN 4:9-10'), findsOneWidget);

      // Switch to Commentary tab
      await tester.tap(find.text('Commentary (1)'));
      await tester.pumpAndSettle();

      expect(find.text('only begotten / one and only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders split view on expanded desktop/tablet (840px)',
        (tester) async {
      tester.view.physicalSize = const Size(1000 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            versionLabel: 'World English Bible',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '1JN:4:9': 'By this God’s love was revealed in us...',
            },
            commentaryNotes: const [sampleNote],
            baseFontSize: 16.0,
            initialTab: 1,
          ),
          size: const Size(1000, 800),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Study (JHN 3:16)'), findsOneWidget);
      expect(find.text('only begotten / one and only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
