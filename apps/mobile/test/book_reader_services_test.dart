import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/book_chapter.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/services/book_reader_appearance.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/features/books/services/page_loader.dart';
import 'package:mobile/features/books/services/reading_position_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('ReadingPositionTracker Unit Tests', () {
    const chapters = [
      BookChapter(
        bookId: 'b',
        chapterIndex: 1,
        chapterTitle: 'The Beginning',
        startPage: 1,
        startLine: 1,
        endPage: 5,
        endLine: 120,
      ),
      BookChapter(
        bookId: 'b',
        chapterIndex: 2,
        chapterTitle: 'The Growth',
        startPage: 6,
        startLine: 121,
        endPage: 10,
        endLine: 250,
      ),
    ];

    test('chapterTitleForPage resolves by page range', () {
      expect(ReadingPositionTracker.chapterTitleForPage(chapters, 3), 'The Beginning');
      expect(ReadingPositionTracker.chapterTitleForPage(chapters, 7), 'The Growth');
      expect(ReadingPositionTracker.chapterTitleForPage(chapters, 999), '');
    });

    test('completionForLine clamps into 0..1', () {
      expect(ReadingPositionTracker.completionForLine(startLine: 0, totalLines: 100), 0.0);
      expect(ReadingPositionTracker.completionForLine(startLine: 50, totalLines: 100), 0.5);
      expect(ReadingPositionTracker.completionForLine(startLine: 200, totalLines: 100), 1.0);
      expect(ReadingPositionTracker.completionForLine(startLine: -5, totalLines: 100), 0.0);
      // Unknown total lines -> 0
      expect(ReadingPositionTracker.completionForLine(startLine: 50, totalLines: 0), 0.0);
    });

    test('completionForPage maps page to fraction', () {
      expect(ReadingPositionTracker.completionForPage(pageNumber: 5, totalPages: 10), 0.5);
      expect(ReadingPositionTracker.completionForPage(pageNumber: 10, totalPages: 10), 1.0);
    });

    test('completionForPageLines prefers first line, falls back to page', () {
      const lines = [
        BookLine(bookId: 'b', pageNumber: 2, lineNumber: 41, chapterIndex: 1, text: 'x'),
        BookLine(bookId: 'b', pageNumber: 2, lineNumber: 42, chapterIndex: 1, text: 'y'),
      ];
      // Uses line 41 / 400 total
      expect(
        ReadingPositionTracker.completionForPageLines(lines, pageNumber: 2, totalLines: 400, totalPages: 50),
        closeTo(41 / 400, 0.0001),
      );
      // Empty lines falls back to page fraction
      expect(
        ReadingPositionTracker.completionForPageLines(const [], pageNumber: 25, totalLines: 400, totalPages: 50),
        0.5,
      );
    });

    test('safeTotalPages never returns < 1', () {
      expect(ReadingPositionTracker.safeTotalPages(null), 1);
      const zero = Book(id: 'x', title: 'x', author: '', description: '', coverFile: '', totalPages: 0, totalLines: 0, createdAt: '');
      expect(ReadingPositionTracker.safeTotalPages(zero), 1);
      const ok = Book(id: 'x', title: 'x', author: '', description: '', coverFile: '', totalPages: 63, totalLines: 1753, createdAt: '');
      expect(ReadingPositionTracker.safeTotalPages(ok), 63);
    });

    test('ReadingBlockKey round-trips page and startLine', () {
      final key = ReadingBlockKey.of(7, 12);
      expect(key, '7:12');
      final parsed = ReadingBlockKey.parse(key);
      expect(parsed, (7, 12));
    });

    test('ReadingBlockKey.parse rejects malformed keys', () {
      expect(ReadingBlockKey.parse('no-colon'), isNull);
      expect(ReadingBlockKey.parse('a:b'), isNull);
      expect(ReadingBlockKey.parse('7:'), isNull);
    });
  });

  group('PageLoader spread & preload logic Unit Tests', () {
    test('spreadLeftForPage pairs odd-valued left pages', () {
      expect(PageLoader.spreadLeftForPage(1, 20), 1);
      expect(PageLoader.spreadLeftForPage(2, 20), 1);
      expect(PageLoader.spreadLeftForPage(3, 20), 3);
      expect(PageLoader.spreadLeftForPage(4, 20), 3);
      expect(PageLoader.spreadLeftForPage(20, 20), 19);
      expect(PageLoader.spreadLeftForPage(0, 20), 1);
      expect(PageLoader.spreadLeftForPage(99, 20), 19);
    });
  });

  group('PageLoader fetch & cache Unit Tests', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      BookService.instance.overrideDbPath = inMemoryDatabasePath;
      await BookService.instance.initialize();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<String> seedBook() async {
      final db = (await BookService.instance.database as Database?)!;
      final id = 'pl_${DateTime.now().microsecondsSinceEpoch}';
      await db.insert('books', {
        'id': id,
        'title': 'Page Loader Test',
        'author': 'Author',
        'subject': 'Christian Living',
        'categories': '["Christian Living"]',
        'description': 'Desc',
        'cover_file': '',
        'total_pages': 10,
        'total_lines': 50,
        'download_size_formatted': '1 MB',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('book_chapters', {
        'book_id': id,
        'chapter_index': 1,
        'chapter_title': 'Chapter 1',
        'start_page': 1,
        'start_line': 1,
        'end_page': 10,
        'end_line': 50,
      });
      for (var p = 1; p <= 10; p++) {
        for (var l = 1; l <= 5; l++) {
          final lineNum = (p - 1) * 5 + l;
          await db.insert('book_content', {
            'book_id': id,
            'page_number': p,
            'line_number': lineNum,
            'chapter_index': 1,
            'content_type': 'p',
            'text': 'Line $lineNum on page $p',
          });
        }
      }
      return id;
    }

    test('fetchPageLines caches lines and reuses cache without refetching', () async {
      final id = await seedBook();
      final loader = PageLoader(BookService.instance, id);

      final lines = await loader.fetchPageLines(3);
      expect(lines, isNotEmpty);
      expect(lines, everyElement(isA<BookLine>()));
      expect(loader.pageCache(3), lines);
      expect(loader.isPageLoading(3), isFalse);
      expect(loader.hasPageFailed(3), isFalse);

      final again = await loader.fetchPageLines(3);
      expect(identical(again, lines), isTrue);
    });

    test('fetchPageLines marks a missing page as failed', () async {
      final id = await seedBook();
      final loader = PageLoader(BookService.instance, id);

      var stateChanges = 0;
      loader.onPageStateChanged = () => stateChanges++;

      final lines = await loader.fetchPageLines(999);
      expect(lines, isEmpty);
      expect(loader.hasPageFailed(999), isTrue);
      expect(loader.pageCache(999), isEmpty);
      expect(stateChanges, greaterThan(0));

      loader.invalidatePage(999);
      expect(loader.hasPageFailed(999), isFalse);
      expect(loader.pageCache(999), isNull);
    });

    test('concurrent fetchPageLines deduplicates in-flight requests', () async {
      final id = await seedBook();
      final loader = PageLoader(BookService.instance, id);

      final results = await Future.wait([
        loader.fetchPageLines(4),
        loader.fetchPageLines(4),
      ]);
      expect(results.first, isNotEmpty);
      expect(results.last, results.first);
      expect(loader.isPageLoading(4), isFalse);
    });

    test('preloadAdjacentPages fetches center then nearby pages', () async {
      final id = await seedBook();
      final loader = PageLoader(BookService.instance, id);
      const book = Book(
        id: 'pl',
        title: 'Page Loader Test',
        author: 'Author',
        description: 'Desc',
        coverFile: '',
        totalPages: 10,
        totalLines: 50,
        createdAt: '',
      );

      await loader.preloadAdjacentPages(5, book);

      // Center page loaded, and neighbors populated (some may be empty if the
      // seed only covers pages 1..10 which all have content).
      expect(loader.pageCache(5), isNotEmpty);
      var populated = 0;
      for (var p = 3; p <= 7; p++) {
        if (loader.pageAvailable(p)) populated++;
      }
      expect(populated, greaterThanOrEqualTo(3));
    });
  });

  group('book_reader_appearance Unit Tests', () {
    const tokensDark = AppTokens.dark;
    const tokensLight = AppTokens.light;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults are serif, 17pt, system theme, 1.65 line height', () {
      final a = BookReaderAppearance();
      expect(a.useSerifFont, isTrue);
      expect(a.fontSize, 17.0);
      expect(a.themeMode, ReaderThemeMode.system);
      expect(a.lineHeight, 1.65);
    });

    test('fontSize setter bounds within 14..26', () {
      final a = BookReaderAppearance();
      a.fontSize = 21.5;
      expect(a.fontSize, 21.5);
      a.fontSize = 5; // ignored
      expect(a.fontSize, 21.5);
      a.fontSize = 99; // ignored
      expect(a.fontSize, 21.5);
    });

    test('lineHeight setter bounds within 1.0..2.5', () {
      final a = BookReaderAppearance();
      a.lineHeight = 2.0;
      expect(a.lineHeight, 2.0);
      a.lineHeight = 0.1; // ignored
      expect(a.lineHeight, 2.0);
    });

    test('theme colors map correctly', () {
      final a = BookReaderAppearance()..themeMode = ReaderThemeMode.sepia;
      expect(a.background(tokensDark), const Color(0xFFFBF0D9));
      expect(a.textColor(tokensDark), const Color(0xFF3B2F2F));

      a.themeMode = ReaderThemeMode.amoled;
      expect(a.background(tokensDark), const Color(0xFF000000));
      expect(a.textColor(tokensDark), const Color(0xFFFFFFFF));

      a.themeMode = ReaderThemeMode.system;
      expect(a.background(tokensLight), tokensLight.background);
      expect(a.textColor(tokensDark), tokensDark.onSurface);
    });

    test('highlight colors map by index', () {
      expect(BookReaderAppearance.highlightColorByIndex(0), const Color(0xFFFFD54F));
      expect(BookReaderAppearance.highlightColorByIndex(1), const Color(0xFF81C784));
      expect(BookReaderAppearance.highlightColorByIndex(2), const Color(0xFF64B5F6));
      expect(BookReaderAppearance.highlightColorByIndex(3), const Color(0xFFF48FB1));
      expect(BookReaderAppearance.highlightColorByIndex(9), const Color(0xFFFFD54F));
    });

    test('loadFromPrefs reads persisted values', () async {
      SharedPreferences.setMockInitialValues({
        'book_reader_font_size': 20.0,
        'book_reader_serif': false,
        'book_reader_theme_mode': 'sepia',
        'book_reader_line_height': 1.9,
      });
      final a = BookReaderAppearance();
      await a.loadFromPrefs();
      expect(a.fontSize, 20.0);
      expect(a.useSerifFont, isFalse);
      expect(a.themeMode, ReaderThemeMode.sepia);
      expect(a.lineHeight, 1.9);
    });

    test('mutating a setting notifies listeners', () {
      final a = BookReaderAppearance();
      var fired = 0;
      a.addListener(() => fired++);
      a.fontSize = 18;
      a.useSerifFont = false;
      a.lineHeight = 2.0;
      a.themeMode = ReaderThemeMode.dark;
      // 4 changes, but each setter notifies exactly once
      expect(fired, 4);
    });
  });
}
