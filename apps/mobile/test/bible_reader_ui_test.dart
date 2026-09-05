import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/controllers/bible_controller.dart';
import 'package:mobile/features/bible/screens/bible_screen.dart';
import 'package:mobile/features/bible/widgets/verse_concept_card.dart';
import 'package:mobile/features/bible/widgets/verse_action_bar.dart';
import 'package:mobile/features/bible/widgets/verse_text.dart';
import 'package:mobile/features/bible/widgets/book_chapter_selector.dart';
import 'package:mobile/features/bible/models/verse_concept.dart';
import 'package:mobile/features/bible/models/bible_verse.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppTokens.dark]),
    home: child,
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_ui_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
    await LocalBibleService.resetForTest();

    final service = LocalBibleService();
    await service.initialize();
    await service.registerInstalledVersion(
      id: 'WEB',
      name: 'World English Bible',
      language: 'English',
      languageCode: 'en',
      sizeDisplay: '1 MB',
    );
    await service.insertVerses('WEB', [
      for (var v = 1; v <= 10; v++)
        {
          'bookNumber': 43,
          'bookName': 'John',
          'chapter': 3,
          'verse': v,
          'text': 'For God so loved the world in verse $v of John 3.',
        },
    ]);
  });

  tearDown(() async {
    LocalBibleService.overrideDbPath = null;
    await LocalBibleService.resetForTest();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('BibleScreen renders without overflow at 320dp viewport', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrapWithApp(
        const BibleScreen(
          initialVersionId: 'WEB',
          initialBook: 'John',
          initialChapter: 3,
          saveProgress: false,
        ),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.pump(const Duration(seconds: 15));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('Previous chapter'), findsOneWidget);
    expect(find.byTooltip('Next chapter'), findsOneWidget);
  });

  testWidgets('Multi-verse selection displays single VerseActionBar with Clear action', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = BibleController(
      initialVersionId: 'WEB',
      initialBook: 'John',
      initialChapter: 3,
      initialVerse: null,
      saveProgress: false,
    );

    await tester.runAsync(() async {
      await controller.init();
    });

    await tester.pumpWidget(wrapWithApp(BibleScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.byType(VerseActionBar), findsNothing);

    // Tap verse 1
    final verseWidgets = find.byType(VerseText);
    expect(verseWidgets, findsWidgets);
    await tester.tap(verseWidgets.at(0), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(VerseActionBar), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);

    // Tap verse 2
    await tester.tap(verseWidgets.at(1), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(VerseActionBar), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);

    // Tap Deselect all (Close icon)
    await tester.tap(find.byTooltip('Deselect all'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(VerseActionBar), findsNothing);
    expect(find.byTooltip('Previous chapter'), findsOneWidget);
  });

  testWidgets('VerseConceptCard renders at 320dp and detects Hebrew RTL vs Greek LTR', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final greekConcept = VerseConcept(
      lemma: 'ἀγάπη',
      conceptId: 'agape',
      conceptName: 'Agape Love',
      definition: 'Unconditional, sacrificial love.',
      biblicalMeaning: 'Divine love.',
      historicalContext: 'Greco-Roman world.',
      culturalContext: 'Early church.',
      citations: [],
      originalLanguage: OriginalLanguage(
        lemma: 'ἀγάπη',
        transliteration: 'agapē',
        strongs: 'G26',
        lexicalMeaning: 'love',
      ),
    );

    final hebrewConcept = VerseConcept(
      lemma: 'בְּרֵאשִׁית',
      conceptId: 'bereshit',
      conceptName: 'Beginning',
      definition: 'In the beginning.',
      biblicalMeaning: 'Creation.',
      historicalContext: 'Ancient Near East.',
      culturalContext: 'Hebrew cosmology.',
      citations: [],
      originalLanguage: OriginalLanguage(
        lemma: 'בְּרֵאשִׁית',
        transliteration: 'bereshit',
        strongs: 'H7225',
        lexicalMeaning: 'first / beginning',
      ),
    );

    await tester.pumpWidget(
      wrapWithApp(
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                VerseConceptCard(concept: greekConcept),
                VerseConceptCard(concept: hebrewConcept),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final textFinders = find.byType(Text);
    expect(textFinders, findsWidgets);

    // Verify Greek text has LTR direction
    final greekTextWidget = tester.widget<Text>(find.text('ἀγάπη'));
    expect(greekTextWidget.textDirection, TextDirection.ltr);

    // Verify Hebrew text has RTL direction
    final hebrewTextWidget = tester.widget<Text>(find.text('בְּרֵאשִׁית'));
    expect(hebrewTextWidget.textDirection, TextDirection.rtl);
  });

  testWidgets('BookChapterSelector adapts to screen width with MaxCrossAxisExtent', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrapWithApp(
        BookChapterSelector(
          currentBook: 'John',
          currentChapter: 3,
          onSelection: (book, chapter, verse) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('BOOKS'), findsOneWidget);
    expect(find.text('CHAPTERS'), findsOneWidget);
    expect(find.text('VERSES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BookChapterSelector picks book, chapter, then verse', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? selectedBook;
    int? selectedChapter;
    int? selectedVerse;
    await tester.pumpWidget(
      wrapWithApp(
        BookChapterSelector(
          currentBook: 'John',
          currentChapter: 3,
          currentVerse: 16,
          loadVerses: (book, chapter) async => [
            for (var v = 1; v <= 50; v++)
              BibleVerse(number: v, text: 'Verse $v of $book $chapter'),
          ],
          onSelection: (book, chapter, verse) {
            selectedBook = book;
            selectedChapter = chapter;
            selectedVerse = verse;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Books tab: pick John, which advances to the chapters tab.
    await tester.tap(find.text('John'));
    await tester.pumpAndSettle();

    // Chapters tab: pick chapter 3, which loads verses and advances.
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    // Verses tab: the grid filled with verse numbers; tap verse 16.
    expect(find.text('VERSES'), findsOneWidget);
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();

    expect(selectedBook, 'John');
    expect(selectedChapter, 3);
    expect(selectedVerse, 16);
    expect(tester.takeException(), isNull);
  });
}
