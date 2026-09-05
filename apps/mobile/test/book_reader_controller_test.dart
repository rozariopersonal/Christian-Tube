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
}
