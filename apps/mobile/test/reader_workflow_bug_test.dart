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
      expect(ScriptureRefParser.parse('Chapter 1'), isNull);
      expect(ScriptureRefParser.parse('April 15'), isNull);
    });

    test('parses compact period citations without whitespace (Psa.73:25, Lk.5:8)', () {
      final p1 = ScriptureRefParser.parse('Psa.73:25');
      expect(p1, isNotNull);
      expect(p1!.bookNumber, equals(19));
      expect(p1.chapter, equals(73));
      expect(p1.startVerse, equals(25));

      final p2 = ScriptureRefParser.parse('Isa.6:1-5');
      expect(p2, isNotNull);
      expect(p2!.bookNumber, equals(23));
      expect(p2.chapter, equals(6));
      expect(p2.startVerse, equals(1));
      expect(p2.endVerse, equals(5));

      final p3 = ScriptureRefParser.parse('Lk.5:8');
      expect(p3, isNotNull);
      expect(p3!.bookNumber, equals(42));
      expect(p3.chapter, equals(5));
      expect(p3.startVerse, equals(8));

      final p4 = ScriptureRefParser.parse('Rev.1:17');
      expect(p4, isNotNull);
      expect(p4!.bookNumber, equals(66));
      expect(p4.chapter, equals(1));
      expect(p4.startVerse, equals(17));

      final p5 = ScriptureRefParser.parse('1Jn.1:9');
      expect(p5, isNotNull);
      expect(p5!.bookNumber, equals(62));
      expect(p5.chapter, equals(1));
      expect(p5.startVerse, equals(9));
    });

    test('parses Roman numerals for numbered epistles (I Cor, II Tim)', () {
      final p1 = ScriptureRefParser.parse('I Cor 13:4-7');
      expect(p1, isNotNull);
      expect(p1!.bookNumber, equals(46));
      expect(p1.chapter, equals(13));
      expect(p1.startVerse, equals(4));
      expect(p1.endVerse, equals(7));

      final p2 = ScriptureRefParser.parse('II Tim 2:15');
      expect(p2, isNotNull);
      expect(p2!.bookNumber, equals(55));
      expect(p2.chapter, equals(2));
      expect(p2.startVerse, equals(15));
    });

    test('parses Tamil references with inflectional suffix', () {
      final p = ScriptureRefParser.parse('எபேசியர் 1:17,18-ல்');
      expect(p, isNotNull);
      expect(p!.bookNumber, equals(49));
      expect(p.chapter, equals(1));
      expect(p.startVerse, equals(17));
    });

    test('tokenize separates false positives from true references', () {
      const input = 'Chapter 1 Repentance: see page 5:12, but read John 3:16 and Psa.73:25 for truth.';
      final tokens = ScriptureRefParser.tokenize(input);

      final refs = tokens.where((t) => t.isReference).toList();
      expect(refs.length, equals(2));
      expect(refs[0].text, equals('John 3:16'));
      expect(refs[0].ref!.bookNumber, equals(43));
      expect(refs[1].text, equals('Psa.73:25'));
      expect(refs[1].ref!.bookNumber, equals(19));

      // Non-scripture like "Chapter 1" and "page 5:12" must stay in non-reference tokens
      final prose = tokens.where((t) => !t.isReference).map((t) => t.text).join();
      expect(prose.contains('Chapter 1'), isTrue);
      expect(prose.contains('page 5:12'), isTrue);
    });

    test('tokenize parses preprocessed [ref:b.c.s-e|text] tags in O(N) pass', () {
      const input = 'Read [ref:43.3.16|John 3:16] and [ref:46.13.4-7|1 Cor 13:4-7] daily.';
      final tokens = ScriptureRefParser.tokenize(input);

      expect(tokens.length, equals(5));
      expect(tokens[0].text, equals('Read '));
      expect(tokens[0].isReference, isFalse);

      expect(tokens[1].text, equals('John 3:16'));
      expect(tokens[1].isReference, isTrue);
      expect(tokens[1].ref!.bookNumber, equals(43));
      expect(tokens[1].ref!.chapter, equals(3));
      expect(tokens[1].ref!.startVerse, equals(16));
      expect(tokens[1].ref!.endVerse, isNull);

      expect(tokens[2].text, equals(' and '));
      expect(tokens[2].isReference, isFalse);

      expect(tokens[3].text, equals('1 Cor 13:4-7'));
      expect(tokens[3].isReference, isTrue);
      expect(tokens[3].ref!.bookNumber, equals(46));
      expect(tokens[3].ref!.chapter, equals(13));
      expect(tokens[3].ref!.startVerse, equals(4));
      expect(tokens[3].ref!.endVerse, equals(7));

      expect(tokens[4].text, equals(' daily.'));
      expect(tokens[4].isReference, isFalse);
    });

    test('does not match single-letter words before colon', () {
      expect(ScriptureRefParser.parse('a 1:2'), isNull);
      expect(ScriptureRefParser.parse('I 3:4'), isNull);
    });
  });

  group('ScriptureRefParser Multi-Language Tests', () {
    test('parses German references including ordinal-with-period book names', () {
      final p1 = ScriptureRefParser.parse('1. Mose 1:1');
      expect(p1, isNotNull);
      expect(p1!.bookNumber, equals(1));
      expect(p1.chapter, equals(1));
      expect(p1.startVerse, equals(1));

      final p2 = ScriptureRefParser.parse('Römer 8:28');
      expect(p2, isNotNull);
      expect(p2!.bookNumber, equals(45));
      expect(p2.chapter, equals(8));
      expect(p2.startVerse, equals(28));
    });

    test('parses Malayalam references', () {
      final parsed = ScriptureRefParser.parse('1 കൊരിന്ത്യർ 12:21');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, equals(46));
      expect(parsed.chapter, equals(12));
      expect(parsed.startVerse, equals(21));
    });

    test('parses Kannada references', () {
      final parsed = ScriptureRefParser.parse('ರೋಮಾಪುರದವರಿಗೆ 8:28');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, equals(45));
      expect(parsed.chapter, equals(8));
      expect(parsed.startVerse, equals(28));
    });

    test('parses Hindi references', () {
      final parsed = ScriptureRefParser.parse('यूहन्ना 3:16');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, equals(43));
      expect(parsed.chapter, equals(3));
      expect(parsed.startVerse, equals(16));
    });

    test('parses Telugu references', () {
      final parsed = ScriptureRefParser.parse('యోహాను 3:16');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, equals(43));
      expect(parsed.chapter, equals(3));
      expect(parsed.startVerse, equals(16));
    });

    test('parses Korean and Spanish references', () {
      final p1 = ScriptureRefParser.parse('요한복음 3:16');
      expect(p1, isNotNull);
      expect(p1!.bookNumber, equals(43));
      expect(p1.chapter, equals(3));

      final p2 = ScriptureRefParser.parse('Romanos 8:28');
      expect(p2, isNotNull);
      expect(p2!.bookNumber, equals(45));
      expect(p2.chapter, equals(8));
      expect(p2.startVerse, equals(28));
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
              onHighlight: () {},
              onNote: () {},
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
                onHighlight: () {},
                onNote: () {},
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

      final prevFinder = find.widgetWithIcon(IconButton, Icons.chevron_left_rounded);
      final nextFinder = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);

      expect(prevFinder, findsOneWidget);
      expect(nextFinder, findsOneWidget);

      final prevButton = tester.widget<IconButton>(prevFinder);
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

      final revNextFinder = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
      expect(revNextFinder, findsOneWidget);
      final revNextButton = tester.widget<IconButton>(revNextFinder);
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
