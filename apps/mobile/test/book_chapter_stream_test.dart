import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/books/services/book_chapter_stream.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Deterministic 3-chapter seed book:
//   ch1: pages 1-2, 3 lines per page  -> 6 lines
//   ch2: pages 3-4, 2 lines per page  -> 4 lines
//   ch3: page 5, 4 lines              -> 4 lines

Future<void> _seedChapter(
  Database db,
  String id,
  int chapter, {
  required int pages,
  required int linesPerPage,
}) async {
  final firstPage = (chapter - 1) * 2 + 1;
  for (var p = 0; p < pages; p++) {
    final pageNumber = firstPage + p;
    for (var l = 1; l <= linesPerPage; l++) {
      await db.insert('book_content', {
        'book_id': id,
        'page_number': pageNumber,
        'line_number': l,
        'chapter_index': chapter,
        'content_type': 'p',
        'text': 'ch$chapter p$pageNumber l$l',
      });
    }
  }
}

void main() {
  late String bookId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BookService.instance.overrideDbPath = inMemoryDatabasePath;
    await BookService.instance.initialize();
  });

  setUp(() async {
    final db = (await BookService.instance.database as Database?)!;
    bookId = 'stream_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('books', {
      'id': bookId,
      'title': 'Stream Test',
      'author': 'Author',
      'subject': 'Christian Living',
      'categories': '["Christian Living"]',
      'description': 'Desc',
      'cover_file': '',
      'total_pages': 5,
      'total_lines': 14,
      'download_size_formatted': '1 MB',
      'created_at': DateTime.now().toIso8601String(),
    });
    for (var ch = 1; ch <= 3; ch++) {
      await db.insert('book_chapters', {
        'book_id': bookId,
        'chapter_index': ch,
        'chapter_title': 'Chapter $ch',
        'start_page': 1 + (ch - 1) * 2,
        'start_line': 1,
        'end_page': ch * 2,
        'end_line': 4,
      });
    }
    await _seedChapter(db, bookId, 1, pages: 2, linesPerPage: 3);
    await _seedChapter(db, bookId, 2, pages: 2, linesPerPage: 2);
    await _seedChapter(db, bookId, 3, pages: 1, linesPerPage: 4);
  });

  BookChapterStream newStream({int? totalChapters = 3}) =>
      BookChapterStream(BookService.instance, bookId,
          totalChapters: totalChapters);

  test('ensureChapter loads, orders, and caches chapter lines', () async {
    final stream = newStream();
    expect(stream.contains(1), isFalse);

    final lines = await stream.ensureChapter(1);
    expect(stream.contains(1), isTrue);
    expect(lines, hasLength(6));
    expect(lines.first.pageNumber, 1);
    expect(lines.first.lineNumber, 1);
    expect(lines[3].pageNumber, 2);
    expect(lines.last.text, 'ch1 p2 l3');

    final again = await stream.ensureChapter(1);
    expect(identical(again, lines), isTrue,
        reason: 'cached chapters resolve the same instance');
  });

  test('concurrent ensureChapter deduplicates in-flight requests', () async {
    final stream = newStream();
    final results = await Future.wait([
      stream.ensureChapter(2),
      stream.ensureChapter(2),
      stream.ensureChapter(2),
    ]);
    expect(results.first, hasLength(4));
    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[1], results[2]), isTrue);
    expect(stream.contains(2), isTrue);
  });

  test('onChapterResolved reports discovered chapter lengths', () async {
    final stream = newStream();
    final probes = <int, int>{};
    stream.onChapterResolved = (chapterIndex, lineCount) {
      probes[chapterIndex] = lineCount;
    };

    await stream.ensureChapter(1);
    await stream.ensureChapter(3);

    expect(probes, {1: 6, 3: 4});
  });

  test('preloadAround warms neighbors and honors chapter bounds', () async {
    final stream = newStream();
    await stream.ensureChapter(2);

    stream.preloadAround(2, radius: 2);

    final ch1 = await stream.ensureChapter(1);
    final ch3 = await stream.ensureChapter(3);
    expect(ch1, hasLength(6));
    expect(ch3, hasLength(4));

    expect(stream.contains(1), isTrue);
    expect(stream.contains(3), isTrue);
    expect(stream.bufferedCount, 3);
  });

  test('missing chapter on an installed book resolves empty, not failed',
      () async {
    final stream = newStream();

    final lines = await stream.ensureChapter(999);
    expect(lines, isEmpty);
    expect(stream.contains(999), isTrue);
    expect(stream.hasFailed(999), isFalse,
        reason: 'adapter reported success with no rows');
  });

  test('clear drops every buffered chapter', () async {
    final stream = newStream();
    await stream.ensureChapter(1);

    stream.clear();
    expect(stream.contains(1), isFalse);
    expect(stream.bufferedCount, 0);

    final lines = await stream.ensureChapter(1);
    expect(lines, hasLength(6));
  });
}