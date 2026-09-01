import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/book_chapter.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/models/book_scripture_link.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/book_card.dart';
import 'package:mobile/features/books/widgets/book_cover_fallback.dart';
import 'package:mobile/features/dictionary/models/dictionary_entry.dart';
import 'package:mobile/features/dictionary/services/dictionary_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Book Models Unit Tests', () {
    test('Book serialization', () {
      const book = Book(
        id: 'living_as_jesus_lived',
        title: 'Living As Jesus Lived',
        author: 'Zac Poonen',
        description: 'A study on Christ our forerunner.',
        coverFile: 'living_as_jesus_lived.jpg',
        totalPages: 63,
        totalLines: 1753,
        createdAt: '2026-09-01T00:00:00Z',
      );

      final map = book.toMap();
      final restored = Book.fromMap(map);
      expect(restored.id, 'living_as_jesus_lived');
      expect(restored.title, 'Living As Jesus Lived');
      expect(restored.totalPages, 63);
    });

    test('BookChapter serialization', () {
      const chapter = BookChapter(
        bookId: 'living_as_jesus_lived',
        chapterIndex: 3,
        chapterTitle: 'Living In Holiness',
        startPage: 13,
        startLine: 1,
        endPage: 20,
        endLine: 28,
      );

      final map = chapter.toMap();
      final restored = BookChapter.fromMap(map);
      expect(restored.chapterTitle, 'Living In Holiness');
      expect(restored.startPage, 13);
    });

    test('BookLine serialization', () {
      const line = BookLine(
        bookId: 'living_as_jesus_lived',
        pageNumber: 13,
        lineNumber: 17,
        chapterIndex: 3,
        contentType: 'h2',
        text: 'looking unto Him Who has run the race ahead of us',
      );

      final map = line.toMap();
      final restored = BookLine.fromMap(map);
      expect(restored.text, contains('looking unto Him'));
      expect(restored.contentType, 'h2');
    });

    test('BookHighlight serialization', () {
      const highlight = BookHighlight(
        id: 'hl_123',
        bookId: 'beauty_for_ashes',
        chapterIndex: 2,
        pageNumber: 5,
        startChar: 10,
        endChar: 45,
        text: 'God turns our sorrow into joy',
        color: 1,
        createdAt: '2026-09-01T12:00:00Z',
      );

      final map = highlight.toMap();
      final restored = BookHighlight.fromMap(map);
      expect(restored.id, 'hl_123');
      expect(restored.text, 'God turns our sorrow into joy');
      expect(restored.color, 1);
    });

    test('ScriptureRefParser parses verse references correctly', () {
      final parsed = ScriptureRefParser.parse('Romans 8:28');
      expect(parsed, isNotNull);
      expect(parsed!.bookNumber, 45);
      expect(parsed.bookName, 'Romans');
      expect(parsed.chapter, 8);
      expect(parsed.startVerse, 28);
      expect(parsed.endVerse, isNull);

      final parsedRange = ScriptureRefParser.parse('1 Cor 13:4-8');
      expect(parsedRange, isNotNull);
      expect(parsedRange!.bookNumber, 46);
      expect(parsedRange.chapter, 13);
      expect(parsedRange.startVerse, 4);
      expect(parsedRange.endVerse, 8);
    });

    test('DictionaryService cleanWord cleans punctuation', () {
      final service = DictionaryService();
      expect(service.cleanWord('sanctification,'), 'sanctification');
      expect(service.cleanWord('"righteousness"'), 'righteousness');
      expect(service.cleanWord('grace.'), 'grace');
    });

    test('DictionaryEntry serialization', () {
      const entry = DictionaryEntry(
        headword: 'grace',
        partOfSpeech: 'noun',
        phonetic: '/ɡreɪs/',
        definition: 'Unmerited divine favor and empowering presence.',
        source: 'English Dictionary',
      );
      expect(entry.headword, 'grace');
      expect(entry.partOfSpeech, 'noun');
      final map = entry.toMap();
      final restored = DictionaryEntry.fromMap(map);
      expect(restored.headword, 'grace');
    });

    test('BookScriptureLink serialization and copyWith', () {
      const link = BookScriptureLink(
        id: 1,
        bookNumber: 58,
        chapter: 12,
        verse: 1,
        endVerse: 1,
        bookId: 'living_as_jesus_lived',
        bookTitle: 'Living As Jesus Lived',
        author: 'Zac Poonen',
        pageNumber: 13,
        startLine: 15,
        endLine: 20,
        headline: 'Chapter 3 Living In Holiness',
      );

      expect(link.bookNumber, 58);
      expect(link.chapter, 12);
      expect(link.verse, 1);

      final withExcerpt = link.copyWith(excerpt: 'We too can run with endurance');
      expect(withExcerpt.excerpt, 'We too can run with endurance');
    });

    test('UserReadingProgress serialization', () {
      const progress = UserReadingProgress(
        bookId: 'living_as_jesus_lived',
        currentPage: 13,
        currentLine: 15,
        completionPercent: 0.21,
        lastReadAt: '2026-09-01T12:00:00Z',
      );

      final map = progress.toMap();
      final restored = UserReadingProgress.fromMap(map);
      expect(restored.currentPage, 13);
      expect(restored.completionPercent, 0.21);
    });
  });

  group('Book Widgets Adaptive UI Tests (AGENTS.md)', () {
    Widget buildFrame(Widget child, {Size size = const Size(360, 640)}) {
      return MaterialApp(
        theme: ThemeData(
          extensions: const [AppTokens.dark],
        ),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(body: Center(child: child)),
        ),
      );
    }

    testWidgets('BookCoverFallback renders at 320, 600, 840, and 1400px without overflow', (tester) async {
      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildFrame(
            const SizedBox(
              width: 140,
              height: 210,
              child: BookCoverFallback(
                title: 'Beauty For Ashes',
                author: 'Zac Poonen',
              ),
            ),
            size: Size(width, 800),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Beauty For Ashes'), findsOneWidget);
        expect(find.text('Zac Poonen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('BookCard renders with progress indicator', (tester) async {
      final book = Book(
        id: 'test_book',
        title: 'Test Book Title',
        author: 'Zac Poonen',
        description: 'Test Description',
        coverFile: '',
        totalPages: 50,
        totalLines: 1000,
        createdAt: '2026-09-01',
      );

      final progress = UserReadingProgress(
        bookId: 'test_book',
        currentPage: 25,
        currentLine: 1,
        completionPercent: 0.5,
        lastReadAt: '2026-09-01',
      );

      await tester.pumpWidget(
        buildFrame(
          SizedBox(
            width: 150,
            height: 250,
            child: BookCard(
              book: book,
              progress: progress,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Book Title'), findsNWidgets(2));
      expect(find.text('50%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
