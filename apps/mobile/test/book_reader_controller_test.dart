import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BookService.instance.overrideDbPath = inMemoryDatabasePath;
    await BookService.instance.initialize();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<String> seedBook({int pages = 20, int lines = 100}) async {
    final db = (await BookService.instance.database as Database?)!;
    final id = 'ctrl_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('books', {
      'id': id,
      'title': 'Controller Book',
      'author': 'Author',
      'subject': 'Christian Living',
      'categories': '["Christian Living"]',
      'description': 'Desc',
      'cover_file': '',
      'total_pages': pages,
      'total_lines': lines,
      'download_size_formatted': '1 MB',
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('book_chapters', {
      'book_id': id,
      'chapter_index': 1,
      'chapter_title': 'Chapter 1: Start',
      'start_page': 1,
      'start_line': 1,
      'end_page': pages,
      'end_line': lines,
    });
    for (var p = 1; p <= pages; p++) {
      for (var l = 1; l <= 5; l++) {
        final lineNum = (p - 1) * 5 + l;
        await db.insert('book_content', {
          'book_id': id,
          'page_number': p,
          'line_number': lineNum,
          'chapter_index': 1,
          'content_type': 'p',
          'text': p == 1 && l == 1 ? 'Chapter 1: Start' : 'Line $lineNum text on page $p',
        });
      }
    }
    return id;
  }

  /// Two-chapter book: ch1 pages 1–10 (lines 1–50), ch2 pages 11–20 (lines
  /// 51–100), 5 lines per page.
  Future<String> seedMultiChapterBook() async {
    final db = (await BookService.instance.database as Database?)!;
    final id = 'multi_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('books', {
      'id': id,
      'title': 'Multi Chapter Book',
      'author': 'Author',
      'subject': 'Christian Living',
      'categories': '["Christian Living"]',
      'description': 'Desc',
      'cover_file': '',
      'total_pages': 20,
      'total_lines': 100,
      'download_size_formatted': '1 MB',
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('book_chapters', {
      'book_id': id,
      'chapter_index': 1,
      'chapter_title': 'Chapter 1: Start',
      'start_page': 1,
      'start_line': 1,
      'end_page': 10,
      'end_line': 50,
    });
    await db.insert('book_chapters', {
      'book_id': id,
      'chapter_index': 2,
      'chapter_title': 'Chapter 2: Middle',
      'start_page': 11,
      'start_line': 51,
      'end_page': 20,
      'end_line': 100,
    });
    for (var p = 1; p <= 20; p++) {
      for (var l = 1; l <= 5; l++) {
        final lineNum = (p - 1) * 5 + l;
        await db.insert('book_content', {
          'book_id': id,
          'page_number': p,
          'line_number': lineNum,
          'chapter_index': p <= 10 ? 1 : 2,
          'content_type': 'p',
          'text': 'Line $lineNum text on page $p',
        });
      }
    }
    return id;
  }

  test('controller loads a book and resolves resume position', () async {
    final id = await seedBook(pages: 20, lines: 100);
    await BookService.instance.saveProgress(id, 10, 45, 0.45);

    final controller = BookReaderController(BookService.instance, id);
    await controller.load();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.book, isNotNull);
    expect(controller.state.currentPage, 10);
    expect(controller.state.lastReadLine, 45);
    expect(controller.state.lastPercent, closeTo(0.45, 0.0001));
    expect(controller.state.prevPages, contains(8));
    expect(controller.state.nextPages, contains(10));
    expect(controller.hasPendingResume, isTrue);
    controller.dispose();
  });

  test('controller starts at initialPage when provided', () async {
    final id = await seedBook();
    await BookService.instance.saveProgress(id, 3, 10, 0.1);

    final controller = BookReaderController(BookService.instance, id, initialPage: 15);
    await controller.load();

    expect(controller.state.currentPage, 15);
    controller.dispose();
  });

  test('controller handles missing book without throwing', () async {
    final controller = BookReaderController(BookService.instance, 'does_not_exist_xyz');
    await controller.load();
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.book, isNull);
    controller.dispose();
  });

  test('markProgress updates state and arms idle timer', () async {
    final controller = BookReaderController(BookService.instance, 'any');
    controller.markProgress(7, 30, 0.3);
    expect(controller.state.currentPage, 7);
    expect(controller.state.lastReadLine, 30);
    expect(controller.hasUnsavedProgress, isTrue);
    controller.dispose();
  });

  test('toggleChrome and setVisiblePage update state and notify', () async {
    final controller = BookReaderController(BookService.instance, 'any');
    var fired = 0;
    controller.addListener(() => fired++);
    expect(controller.state.showChrome, isTrue);

    controller.toggleChrome();
    expect(controller.state.showChrome, isFalse);

    controller.setVisiblePage(5);
    expect(controller.state.currentPage, 5);
    expect(fired, 2);
    controller.dispose();
  });

  test('recenterOnPage rebuilds buffer around target', () async {
    final controller = BookReaderController(BookService.instance, 'any');
    controller.recenterOnPage(10, 20);
    expect(controller.state.centerPage, 10);
    expect(controller.state.prevPages, [9, 8]);
    expect(controller.state.nextPages, [10, 11, 12]);
    controller.dispose();
  });

  test('extendPagesDown and extendPagesUp grow buffers', () async {
    final controller = BookReaderController(BookService.instance, 'any');
    controller.extendPagesUp(4, 3);
    controller.extendPagesDown(6, 7);
    expect(controller.state.prevPages, [4, 3]);
    expect(controller.state.nextPages, [1, 6, 7]);
    controller.dispose();
  });

  test('currentChapterTitle resolves from chapters', () async {
    final id = await seedBook();
    final controller = BookReaderController(BookService.instance, id);
    await controller.load();
    controller.setVisiblePage(8);
    expect(controller.currentChapterTitle(), 'Chapter 1: Start');
    controller.dispose();
  });

  test('appearance is exposed with defaults and supports theming', () {
    final controller = BookReaderController(BookService.instance, 'any');
    expect(controller.appearance, isA<ReaderAppearance>());
    expect(controller.appearance.useSerifFont, isTrue);
    controller.appearance.themeMode = ReaderThemeMode.sepia;
    expect(controller.appearance.themeMode, ReaderThemeMode.sepia);
    controller.dispose();
  });

  test('completionForPage computes percentage based on total pages', () async {
    final id = await seedBook(pages: 20, lines: 100);
    final controller = BookReaderController(BookService.instance, id);
    await controller.load();

    expect(controller.completionForPage(1), closeTo(1 / 20, 0.001));
    expect(controller.completionForPage(5), closeTo(0.25, 0.001));
    expect(controller.completionForPage(10), closeTo(0.50, 0.001));
    expect(controller.completionForPage(20), closeTo(1.0, 0.001));
    controller.dispose();
  });

  test('continuous load resolves an exact deep resume row and arms pending resume', () async {
    final id = await seedMultiChapterBook();

    final controller = BookReaderController(
      BookService.instance,
      id,
      initialPage: 12,
      highlightStartLine: 55,
      useContinuous: true,
    );
    await controller.load();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.chapters.length, 2);
    // Page 12's lines are 56–60 (offsets 5–9 within chapter 2, which begins at
    // row 50), so target line 55 resolves to row 55, not row 0.
    expect(controller.state.resumeRow, 55);
    expect(controller.state.currentPage, 12);
    expect(controller.hasPendingResume, isTrue);
    controller.dispose();
  });

  test('continuous resume from saved progress restores a non-zero row', () async {
    final id = await seedMultiChapterBook();
    await BookService.instance.saveProgress(id, 15, 72, 0.75);

    final controller = BookReaderController(
      BookService.instance,
      id,
      useContinuous: true,
    );
    await controller.load();

    expect(controller.state.currentPage, 15);
    expect(controller.state.lastReadLine, 72);
    // Page 15 lines are 71–75 and sit at offsets 20–24 within chapter 2, so
    // the first line >= 72 lands at row 50 + 21.
    expect(controller.state.resumeRow, 71);
    expect(controller.hasPendingResume, isTrue);
    controller.dispose();
  });

  test('ensureRowsUpTo buffers the contiguous prefix for a later jump', () async {
    final id = await seedMultiChapterBook();

    final controller = BookReaderController(
      BookService.instance,
      id,
      initialPage: 1,
      highlightStartLine: 1,
      useContinuous: true,
    );
    await controller.load();
    // Loading at page 1 buffers only chapter 1 (rows 0–49).
    expect(controller.lineIndex!.knownRowCount, lessThan(80));

    await controller.ensureRowsUpTo(80);

    expect(controller.lineIndex!.knownRowCount, greaterThan(80));
    controller.dispose();
  });
}
