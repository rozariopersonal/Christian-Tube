import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/book_chapter.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/models/book_scripture_link.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/book_card.dart';
import 'package:mobile/features/books/widgets/book_cover_fallback.dart';
import 'package:mobile/features/books/widgets/book_toc_sheet.dart';
import 'package:mobile/features/dictionary/models/dictionary_entry.dart';
import 'package:mobile/features/dictionary/services/dictionary_service.dart';
import 'package:mobile/features/books/screens/book_reader_screen.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BookService.instance.overrideDbPath = inMemoryDatabasePath;
    await BookService.instance.initialize();
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

    test('BookParagraphGrouper groups consecutive lines into a single continuous paragraph', () {
      const lines = [
        BookLine(
          bookId: 'a_good_foundation',
          pageNumber: 2,
          lineNumber: 1,
          chapterIndex: 1,
          contentType: 'p',
          text: 'Yet the sad truth is that most Christians who claim to have accepted the gospel do not live this life.',
        ),
        BookLine(
          bookId: 'a_good_foundation',
          pageNumber: 2,
          lineNumber: 2,
          chapterIndex: 1,
          contentType: 'p',
          text: 'The purpose of this book is to enable you to lay a good foundation in your spiritual journey.',
        ),
        BookLine(
          bookId: 'a_good_foundation',
          pageNumber: 2,
          lineNumber: 3,
          chapterIndex: 1,
          contentType: 'p',
          text: 'Read on then and let the Holy Spirit speak to your heart.',
        ),
      ];

      final blocks = BookParagraphGrouper.groupLines(lines);
      // All 3 lines belong to the same continuous paragraph, so only 1 paragraph block is produced
      expect(blocks.length, 1);
      expect(blocks.first.type, 'p');
      expect(blocks.first.text, contains('Yet the sad truth is that most Christians'));
      expect(blocks.first.text, contains('The purpose of this book is to enable you'));
      expect(blocks.first.text, contains('Read on then and let the Holy Spirit'));
      expect(blocks.first.startLine, 1);
      expect(blocks.first.endLine, 3);
    });

    test('BookParagraphGrouper isolates chapter headers and deduplicates redundant subheadings', () {
      const lines = [
        BookLine(
          bookId: 'beauty_for_ashes',
          pageNumber: 1,
          lineNumber: 1,
          chapterIndex: 1,
          contentType: 'chapter_header',
          text: 'Chapter 0 Introduction',
        ),
        BookLine(
          bookId: 'beauty_for_ashes',
          pageNumber: 1,
          lineNumber: 2,
          chapterIndex: 1,
          contentType: 'h3',
          text: 'Chapter 0 Introduction',
        ),
        BookLine(
          bookId: 'beauty_for_ashes',
          pageNumber: 1,
          lineNumber: 3,
          chapterIndex: 1,
          contentType: 'p',
          text: 'God had a great and glorious purpose for man when He created him.',
        ),
      ];

      final blocks = BookParagraphGrouper.groupLines(lines);
      expect(blocks.length, 2);
      expect(blocks[0].type, 'chapter_header');
      expect(blocks[0].badge?.toUpperCase(), 'CHAPTER 0');
      expect(blocks[0].title, 'Introduction');
      expect(blocks[1].type, 'p');
      expect(blocks[1].text, contains('God had a great and glorious purpose'));
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
      const book = Book(
        id: 'test_book',
        title: 'Test Book Title',
        author: 'Zac Poonen',
        description: 'Test Description',
        coverFile: '',
        totalPages: 50,
        totalLines: 1000,
        createdAt: '2026-09-01',
      );

      const progress = UserReadingProgress(
        bookId: 'test_book',
        currentPage: 25,
        currentLine: 1,
        completionPercent: 0.5,
        lastReadAt: '2026-09-01',
      );

      await tester.pumpWidget(
        buildFrame(
          const SizedBox(
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

    testWidgets('BookTocSheet hides page numbers on mobile and shows on large screens', (tester) async {
      const chapters = [
        BookChapter(
          bookId: 'test_book',
          chapterIndex: 1,
          chapterTitle: 'Introduction',
          startPage: 1,
          startLine: 1,
          endPage: 5,
          endLine: 100,
        ),
      ];

      // 1. Mobile mode (showPageNumbers = false)
      await tester.pumpWidget(
        buildFrame(
          BookTocSheet(
            bookTitle: 'Test Book',
            chapters: chapters,
            currentPage: 1,
            showPageNumbers: false,
            onSelectPage: (_) {},
          ),
          size: const Size(360, 640),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Introduction'), findsOneWidget);
      expect(find.text('p. 1'), findsNothing);

      // 2. Large screen mode (showPageNumbers = true)
      await tester.pumpWidget(
        buildFrame(
          BookTocSheet(
            bookTitle: 'Test Book',
            chapters: chapters,
            currentPage: 1,
            showPageNumbers: true,
            onSelectPage: (_) {},
          ),
          size: const Size(1000, 800),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Introduction'), findsOneWidget);
      expect(find.text('p. 1'), findsOneWidget);
    });

    testWidgets('BookReaderScreen loads appearance preferences and renders across viewports without overflow', (tester) async {
      SharedPreferences.setMockInitialValues({
        'book_reader_font_size': 20.0,
        'book_reader_serif': false,
        'book_reader_theme_mode': 'sepia',
      });

      for (final width in [320.0, 600.0, 840.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: const [AppTokens.dark],
            ),
            home: const BookReaderScreen(bookId: 'test_book_id'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('BookService and BookReaderScreen render real book chapters and lines', (tester) async {
      await tester.runAsync(() async {
        final bookService = BookService.instance;
        final db = (await bookService.database as Database?)!;

        // Insert mock book data
        await db.insert('books', {
          'id': 'mock_book',
          'title': 'Mock Book Title',
          'author': 'Author Name',
          'subject': 'Christian Living',
          'categories': '["Christian Living"]',
          'description': 'A mock book for testing.',
          'cover_file': 'mock.jpg',
          'total_pages': 5,
          'total_lines': 50,
          'download_size_formatted': '1 MB',
          'created_at': DateTime.now().toIso8601String(),
        });

        await db.insert('book_chapters', {
          'book_id': 'mock_book',
          'chapter_index': 1,
          'chapter_title': 'Chapter 1: The Beginning',
          'start_page': 1,
          'start_line': 1,
          'end_page': 3,
          'end_line': 30,
        });

        await db.insert('book_content', {
          'book_id': 'mock_book',
          'page_number': 1,
          'line_number': 1,
          'chapter_index': 1,
          'content_type': 'chapter_header',
          'text': 'Chapter 1: The Beginning',
        });

        await db.insert('book_content', {
          'book_id': 'mock_book',
          'page_number': 1,
          'line_number': 2,
          'chapter_index': 1,
          'content_type': 'p',
          'text': 'This is the first paragraph of the mock book. Check John 3:16 for salvation.',
        });

        // Test BookService queries
        final book = await bookService.getBook('mock_book');
        expect(book, isNotNull);
        expect(book!.title, 'Mock Book Title');

        final chapters = await bookService.getChapters('mock_book');
        final lines = await bookService.getPageLines('mock_book', 1);

        // Verify getChapters and getPageLines read from SQLite
        expect(chapters, isNotEmpty, reason: 'getChapters should return chapters from SQLite database');
        expect(chapters.first.chapterTitle, 'Chapter 1: The Beginning');
        expect(lines, hasLength(2), reason: 'getPageLines should return lines from SQLite database');
      });

      // Now test rendering BookReaderScreen with real content
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [AppTokens.dark],
          ),
          home: const BookReaderScreen(bookId: 'mock_book'),
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Mock Book Title'), findsOneWidget);
      expect(find.textContaining('This is the first paragraph', skipOffstage: false), findsOneWidget);
    });
  });
}
