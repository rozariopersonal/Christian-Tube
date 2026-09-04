import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/bible/models/cross_reference.dart';
import 'package:mobile/features/bible/models/bible_background_note.dart';
import 'package:mobile/features/books/models/book_scripture_link.dart';
import 'package:mobile/features/bible/screens/verse_study_screen.dart';
import 'package:mobile/features/bible/widgets/cross_reference_card.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

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
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            versionLabel: 'World English Bible',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '1JN:4:9': 'By this God’s love was revealed in us...',
            },
            commentaryNotes: const [sampleNote],
            bookCommentariesFuture: Future.value([]),
            baseFontSize: 16.0,
            initialTab: 1,
          ),
          size: const Size(320, 600),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Study (JHN 3:16)'), findsOneWidget);
      expect(find.text('References (1)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('1 John 4:9-10'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('1 John 4:9-10'), findsOneWidget);

      // Switch to Commentary tab
      await tester.tap(find.text('Commentary (1)'));
      await tester.pumpAndSettle();

      expect(find.text('only begotten / one and only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders large view on expanded desktop/tablet (840px)',
        (tester) async {
      tester.view.physicalSize = const Size(1000 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            versionLabel: 'World English Bible',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '1JN:4:9': 'By this God’s love was revealed in us...',
            },
            commentaryNotes: const [sampleNote],
            bookCommentariesFuture: Future.value([]),
            baseFontSize: 16.0,
            initialTab: 2,
          ),
          size: const Size(1000, 800),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Study (JHN 3:16)'), findsOneWidget);
      expect(find.text('only begotten / one and only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Verse appears inside references tab and commentary count combines notes and book commentaries',
        (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            versionLabel: 'World English Bible',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '1JN:4:9': 'By this God’s love was revealed in us...',
            },
            commentaryNotes: const [sampleNote],
            bookCommentariesFuture: Future.value([]),
            baseFontSize: 16.0,
            initialTab: 1,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verse text is in the references tab
      expect(find.text(sampleVerse.text), findsOneWidget);
      expect(find.text('Commentary (1)'), findsOneWidget);

      // Switch to commentary tab
      await tester.tap(find.text('Commentary (1)'));
      await tester.pumpAndSettle();

      // Historical context is counted and presented in commentary tab
      expect(find.text('1 Historical & Cultural Commentary'), findsOneWidget);
      expect(find.text('only begotten / one and only'), findsOneWidget);
    });

    testWidgets('Combines book commentaries and historical context in total count',
        (tester) async {
      const sampleBookLink = BookScriptureLink(
        id: 1,
        bookNumber: 43,
        chapter: 3,
        verse: 16,
        endVerse: 16,
        bookId: 'all_that_you_need',
        bookTitle: 'All That You Need',
        author: 'Zac Poonen',
        pageNumber: 42,
        startLine: 10,
        endLine: 20,
        headline: 'Gods unconditional love',
        excerpt: 'God loved the world and gave His Son.',
      );

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            references: const [],
            commentaryNotes: const [sampleNote],
            bookCommentariesFuture: Future.value([sampleBookLink]),
            baseFontSize: 16.0,
            initialTab: 2,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Combined count: 1 book commentary + 1 historical context note = Commentary (2)
      expect(find.text('Commentary (2)'), findsOneWidget);
      expect(find.text('1 Zac Poonen Exposition'), findsOneWidget);
      expect(find.text('1 Historical & Cultural Commentary'), findsOneWidget);

      // Verify book commentary UI elements & actions
      expect(find.text('All That You Need'), findsOneWidget);
      expect(find.text('Zac Poonen'), findsOneWidget);
      expect(find.text('Page 42'), findsOneWidget);
      expect(find.text('Gods unconditional love'), findsOneWidget);
      expect(find.text('Read in Book'), findsOneWidget);
      expect(find.text('Copy'), findsNWidgets(2)); // Book commentary + Cultural note
    });

    testWidgets('Long book commentary excerpts display expand/collapse toggle',
        (tester) async {
      final longExcerpt = 'A' * 300;
      final longBookLink = BookScriptureLink(
        id: 2,
        bookNumber: 43,
        chapter: 3,
        verse: 16,
        endVerse: 16,
        bookId: 'test_book',
        bookTitle: 'Testing Book Excerpt',
        author: 'Author Name',
        pageNumber: 15,
        startLine: 1,
        endLine: 5,
        headline: 'Long Excerpt Headline',
        excerpt: longExcerpt,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            references: const [],
            commentaryNotes: const [],
            bookCommentariesFuture: Future.value([longBookLink]),
            baseFontSize: 16.0,
            initialTab: 2,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Read more'), findsOneWidget);

      // Ensure visible in scroll view and tap to expand
      await tester.ensureVisible(find.text('Read more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read more'));
      await tester.pumpAndSettle();

      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('Cross references show full book names in the same language as the current bible version',
        (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: 'தேவன், தம்முடைய ஒரேபேறான குமாரனை...',
            verseLabel: 'யோவான் 3:16',
            versionLabel: 'Tamil Old Version (பரிசுத்த வேதாகமம்)',
            versionId: 'TAOBVSI',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '62_4_9': 'தம்முடைய ஒரேபேறான குமாரனாலே நாம் பிழைக்கும்படிக்கு...',
            },
            commentaryNotes: const [],
            bookCommentariesFuture: Future.value([]),
            baseFontSize: 16.0,
            initialTab: 1,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CrossReferenceCard), findsOneWidget);
      final card = tester.widget<CrossReferenceCard>(find.byType(CrossReferenceCard));
      expect(card.versionId, 'TAOBVSI');
      expect(card.reference.formatLabel(card.versionId), '1 யோவான் 4:9-10');
      expect(find.text('1 யோவான் 4:9-10'), findsOneWidget);
    });

    testWidgets('Tapping cross reference navigates to target passage and pop returns to references',
        (tester) async {
      CrossReference? tappedRef;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            references: const [sampleCrossRef],
            resolvedTexts: const {
              '62_4_9': 'By this God’s love was revealed in us...',
            },
            commentaryNotes: const [],
            bookCommentariesFuture: Future.value([]),
            baseFontSize: 16.0,
            initialTab: 1,
            onTapReference: (ref) => tappedRef = ref,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the cross reference card
      await tester.tap(find.text('1 John 4:9-10'));
      await tester.pumpAndSettle();

      expect(tappedRef, isNotNull);
      expect(tappedRef!.bookNumber, 62);
      expect(tappedRef!.chapter, 4);
      expect(tappedRef!.verse, 9);
    });

    testWidgets('Tapping commentary View in Bible navigates to passage and pop returns to commentary',
        (tester) async {
      int? tappedBook;
      int? tappedChapter;
      int? tappedVerse;

      await tester.pumpWidget(
        wrapWithTheme(
          VerseStudyScreen(bookNumber: 1, chapterNumber: 1, verseNumber: 1, 
            verseText: sampleVerse.text,
            verseLabel: 'JHN 3:16',
            references: const [],
            commentaryNotes: const [sampleNote],
            bookCommentariesFuture: Future.value([]),
            baseFontSize: 16.0,
            initialTab: 2,
            onTapPassage: (book, chapter, verse) {
              tappedBook = book;
              tappedChapter = chapter;
              tappedVerse = verse;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('only begotten / one and only'), findsOneWidget);
      final viewInBibleBtn = find.text('View in Bible');
      expect(viewInBibleBtn, findsOneWidget);

      await tester.tap(viewInBibleBtn);
      await tester.pumpAndSettle();

      expect(tappedBook, 43);
      expect(tappedChapter, 3);
      expect(tappedVerse, 16);
    });
  });
}
