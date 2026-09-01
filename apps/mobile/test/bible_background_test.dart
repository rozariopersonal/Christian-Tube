import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/models/bible_background_note.dart';
import 'package:mobile/features/bible/screens/bible_background_screen.dart';
import 'package:mobile/features/bible/widgets/bible_background_sheet.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalBibleService.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('bible_bg_test_');
    LocalBibleService.overrideDbPath = p.join(tempDir.path, 'bible.db');
  });

  tearDown(() async {
    LocalBibleService.resetForTest();
    LocalBibleService.overrideDbPath = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalBibleService bible_backgrounds', () {
    test('insert, query, and delete cultural background notes', () async {
      final service = LocalBibleService();
      await service.initialize();

      expect(await service.hasBibleBackgrounds(), isFalse);

      await service.insertBibleBackgrounds([
        {
          'bookNumber': 40,
          'chapter': 5,
          'verse': 41,
          'id': 'i86s',
          'topic': 'one mile',
          'quote': 'μίλιον ἕν',
          'content':
              'Here, one mile refers to the Roman mile, which was 1,000 paces. In modern measurements, this is about 4,860 feet or 1,480 meters.',
          'source': 'unfoldingWord Cultural Context',
        },
        {
          'bookNumber': 40,
          'chapter': 5,
          'verse': 0,
          'id': 'awz8',
          'topic': 'Chapter Overview',
          'quote': null,
          'content': 'Structure of the Sermon on the Mount.',
          'source': 'unfoldingWord Cultural Context',
        },
      ]);

      expect(await service.hasBibleBackgrounds(), isTrue);

      final chapterNotes = await service.getBackgroundsForChapter(40, 5);
      expect(chapterNotes.keys, containsAll([0, 41]));
      expect(chapterNotes[41]!.single.topic, 'one mile');
      expect(chapterNotes[41]!.single.verse, 41);
      expect(chapterNotes[41]!.single.quote, 'μίλιον ἕν');
      expect(chapterNotes[41]!.single.referenceLabel, 'MAT 5:41');

      final verseNotes = await service.getBackgroundsForVerse(40, 5, 41);
      expect(verseNotes.length, 1);
      expect(verseNotes.first.id, 'i86s');

      await service.deleteBibleBackgrounds();
      expect(await service.hasBibleBackgrounds(), isFalse);
    });
  });

  group('UI Rendering & Responsive Adaptivity', () {
    const testNotes = [
      BibleBackgroundNote(
        bookNumber: 40,
        chapter: 5,
        verse: 41,
        id: 'i86s',
        topic: 'one mile',
        quote: 'μίλιον ἕν',
        text:
            'Here, one mile refers to the Roman mile, which was 1,000 paces. In modern measurements, this is about 4,860 feet or 1,480 meters.',
        source: 'unfoldingWord Cultural Context',
      ),
    ];

    Widget wrapWithTheme(Widget child, {Size size = const Size(360, 640)}) {
      return MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [AppTokens.dark],
        ),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: child,
        ),
      );
    }

    testWidgets('BibleBackgroundSheet renders without overflow at 320px',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          const Scaffold(
            body: BibleBackgroundSheet(
              verseLabel: 'MAT 5:41',
              verseText:
                  'And whoever compels you to go one mile, go with him two.',
              notes: testNotes,
            ),
          ),
          size: const Size(320, 600),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Historical & Cultural Context'), findsOneWidget);
      expect(find.text('one mile'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'BibleBackgroundScreen renders split-view on expanded screen (840px)',
        (tester) async {
      tester.view.physicalSize = const Size(1000 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          const BibleBackgroundScreen(
            verseLabel: 'MAT 5:41',
            verseText:
                'And whoever compels you to go one mile, go with him two.',
            versionLabel: 'World English Bible',
            notes: testNotes,
            baseFontSize: 16.0,
          ),
          size: const Size(1000, 800),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Historical & Cultural Context'), findsOneWidget);
      expect(find.text('one mile'), findsOneWidget);
      expect(find.text('1 historical background note'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
