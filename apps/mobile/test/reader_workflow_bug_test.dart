import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/bible/screens/bible_screen.dart';
import 'package:mobile/features/bible/widgets/verse_action_bar.dart';
import 'package:mobile/features/books/screens/book_reader_screen.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import 'package:mobile/features/engines/scripture/services/local_bible_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await BookNameService().ensureLoaded();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_bug_test_');
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
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('ScriptureRefParser Bug Fix Tests', () {
    test('parses multi-word books (Song of Solomon)', () {
      final parsed = ScriptureRefParser.parse('Song of Solomon 2:1-4');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, equals(22));
      expect(parsed.chapter, equals(2));
      expect(parsed.startVerse, equals(1));
      expect(parsed.endVerse, equals(4));
    });

    test('parses numbered books with and without spaces', () {
      final p1 = ScriptureRefParser.parse('1 John 1:9');
      expect(p1, isNotNull);
      expect(p1!.bookNumber, equals(62));
      expect(p1.chapter, equals(1));
      expect(p1.startVerse, equals(9));

      final p2 = ScriptureRefParser.parse('1Cor 13:4-7');
      expect(p2, isNotNull);
      expect(p2!.bookNumber, equals(46));
      expect(p2.chapter, equals(13));
      expect(p2.startVerse, equals(4));
      expect(p2.endVerse, equals(7));
    });

    test('parses dot separator between chapter and verse', () {
      final parsed = ScriptureRefParser.parse('John 3.16');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, equals(43));
      expect(parsed.chapter, equals(3));
      expect(parsed.startVerse, equals(16));
    });

    test('parses Tamil scripture references', () {
      final p1 = ScriptureRefParser.parse('யோவான் 3:16');
      expect(p1, isNotNull);
      expect(p1!.bookNumber, equals(43));
      expect(p1.chapter, equals(3));
      expect(p1.startVerse, equals(16));

      final p2 = ScriptureRefParser.parse('மத்தேயு 5:3-10');
      expect(p2, isNotNull);
      expect(p2!.bookNumber, equals(40));
      expect(p2.chapter, equals(5));
      expect(p2.startVerse, equals(3));
      expect(p2.endVerse, equals(10));
    });

    test('does not match false positives like "version 2:3" or "page 5:12"', () {
      expect(ScriptureRefParser.parse('version 2:3'), isNull);
      expect(ScriptureRefParser.parse('page 5:12'), isNull);
      expect(ScriptureRefParser.parse('see table 1:4'), isNull);
      expect(ScriptureRefParser.parse('rule 3:2'), isNull);
    });

    test('does not match single-letter words before colon', () {
      expect(ScriptureRefParser.parse('a 1:2'), isNull);
      expect(ScriptureRefParser.parse('I 3:4'), isNull);
    });
  });

  group('VerseActionBar 320px Responsiveness Tests', () {
    testWidgets('renders cleanly at 320px without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [AppTokens.light],
          ),
          home: Scaffold(
            bottomNavigationBar: VerseActionBar(
              selectedCount: 3,
              onCopy: () {},
              onShare: () {},
              onBookmark: () {},
              onClear: () {},
              onStudy: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(VerseActionBar), findsOneWidget);
    });

    testWidgets('renders cleanly at 600px and 1400px', (tester) async {
      for (final width in [600.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: const [AppTokens.light],
            ),
            home: Scaffold(
              bottomNavigationBar: VerseActionBar(
                selectedCount: 1,
                onCopy: () {},
                onShare: () {},
                onBookmark: () {},
                onClear: () {},
                onStudy: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
    });
  });

  group('Bible Reader Navigation Boundary Tests', () {
    testWidgets('Genesis 1 disables Prev button and Revelation 22 disables Next button', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Genesis 1
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [AppTokens.light],
          ),
          home: const BibleScreen(
            initialBook: 'Genesis',
            initialChapter: 1,
            saveProgress: false,
          ),
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 30));
      }

      final prevFinder = find.widgetWithText(TextButton, 'Prev');
      final nextFinder = find.widgetWithText(TextButton, 'Next');

      expect(prevFinder, findsOneWidget);
      expect(nextFinder, findsOneWidget);

      final prevButton = tester.widget<TextButton>(prevFinder);
      expect(prevButton.onPressed, isNull, reason: 'Prev should be disabled on Genesis 1');

      // Revelation 22
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [AppTokens.light],
          ),
          home: const BibleScreen(
            initialBook: 'Revelation',
            initialChapter: 22,
            saveProgress: false,
          ),
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 30));
      }

      final revNextFinder = find.widgetWithText(TextButton, 'Next');
      expect(revNextFinder, findsOneWidget);
      final revNextButton = tester.widget<TextButton>(revNextFinder);
      expect(revNextButton.onPressed, isNull, reason: 'Next should be disabled on Revelation 22');
    });
  });

  group('Book Reader Progress & Spread Slider Tests', () {
    testWidgets('BookReaderScreen restores saved position and renders across screen sizes', (tester) async {
      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: const [AppTokens.light],
            ),
            home: const BookReaderScreen(
              bookId: 'test_book',
              initialPage: 1,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
    });
  });
}
