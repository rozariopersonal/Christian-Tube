import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/services/book_chapter_stream.dart';
import 'package:mobile/features/books/services/book_line_index.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/book_line_item.dart';
import 'package:mobile/features/books/widgets/book_virtual_scroll_content.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

// Deterministic 3-chapter seed book matching book_chapter_stream_test:
//   ch1: pages 1-2, 3 lines per page -> 6 lines
//   ch2: pages 3-4, 2 lines per page -> 4 lines
//   ch3: page 5, 4 lines             -> 4 lines (total 14)

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
    bookId = 'content_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('books', {
      'id': bookId,
      'title': 'Content Test',
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

  Future<BookChapterStream> loadedStream(
      {List<int> chapters = const [1, 2, 3]}) async {
    final stream = BookChapterStream(BookService.instance, bookId,
        totalChapters: 3);
    for (final ch in chapters) {
      await stream.ensureChapter(ch);
    }
    return stream;
  }

  TapGestureRecognizer noopRecognizer(ParsedScriptureRef? parsed, String refText) =>
      TapGestureRecognizer();

  late ItemScrollController itemScrollController;
  late ItemPositionsListener itemPositionsListener;

  setUp(() {
    itemScrollController = ItemScrollController();
    itemPositionsListener = ItemPositionsListener.create();
  });

  Future<void> pumpContent(
    WidgetTester tester, {
    required BookLineIndex index,
    required BookChapterStream stream,
    List<int>? fetchLog,
  }) {
    return tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [AppTokens.light]),
      home: Scaffold(
        body: BookVirtualScrollContent(
          totalLines: index.totalLines,
          totalChapters: 3,
          index: index,
          isChapterLoaded: stream.contains,
          chapterLines: stream.bufferedLines,
          highlightCache: (page) => const <BookHighlight>[],
          appearance: ReaderAppearance(),
          tokens: AppTokens.light,
          textColor: Colors.black,
          itemScrollController: itemScrollController,
          itemPositionsListener: itemPositionsListener,
          makeRecognizer: noopRecognizer,
          onTriggerFetch: fetchLog == null ? (_) {} : fetchLog.add,
          buildSelectionToolbar:
              (context, state) => const SizedBox.shrink(),
        ),
      ),
    ));
  }

  testWidgets(
      'renders buffered rows as content at all breakpoint widths without overflow',
      (tester) async {
    late final BookChapterStream stream;
    late final BookLineIndex index;
    await tester.runAsync(() async {
      stream = await loadedStream();
      index = BookLineIndex(totalLines: 14)
        ..extend(1, 6)
        ..extend(2, 4)
        ..extend(3, 4);
    });

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpContent(tester, index: index, stream: stream);

      expect(find.text('ch1 p1 l1'), findsOneWidget);
      expect(find.byType(BookLineItem), findsWidgets);
      final list = find.byType(ScrollablePositionedList);
      expect(list, findsOneWidget);

      // Scroll a few rows and confirm the stream keeps resolving without
      // exceptions at this size.
      itemScrollController.scrollTo(
        index: 4,
        alignment: 0.0,
        duration: const Duration(milliseconds: 300),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'unloaded chapter rows render placeholders and trigger a chapter fetch, '
      'then swap to real content once resolved', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // ch1 + ch2 are buffered and indexed; ch3 is unknown. Rows for ch3 have a
    // known count of 10, so every row >= 10 must render placeholders and ask
    // for chapter 3.
    late final BookChapterStream stream;
    final index = BookLineIndex(totalLines: 14);
    await tester.runAsync(() async {
      stream = await loadedStream(chapters: [1, 2]);
      stream.onChapterResolved = (chapterIndex, lineCount) {
        index.extend(chapterIndex, lineCount);
      };
      index.extend(1, 6);
      index.extend(2, 4);
    });

    final fetchLog = <int>[];

    await pumpContent(tester, index: index, stream: stream, fetchLog: fetchLog);

    // Jump past the buffered extent so placeholder rows enter the viewport.
    itemScrollController.scrollTo(
      index: 10,
      alignment: 0.0,
      duration: const Duration(milliseconds: 10),
    );
    await tester.pump();
    await tester.pump();

    expect(fetchLog, contains(3), reason: 'viewport reached unknown chapter 3');
    expect(find.byKey(const ValueKey('ph-11')), findsOneWidget);
    expect(find.text('ch3 p5 l1'), findsNothing);

    // Resolve chapter 3; the controller-equivalent index extend happens via
    // the stream's onChapterResolved, and a rebuild swaps the skeleton rows
    // into real text.
    await tester.runAsync(() => stream.ensureChapter(3));
    await pumpContent(tester, index: index, stream: stream, fetchLog: fetchLog);
    await tester.pump();

    expect(find.text('ch3 p5 l1'), findsOneWidget);
    expect(find.byKey(const ValueKey('ph-11')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty book renders nothing', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final index = BookLineIndex(totalLines: 0);
    final stream = BookChapterStream(BookService.instance, bookId,
        totalChapters: 3);

    await pumpContent(tester, index: index, stream: stream);

    expect(find.byType(ScrollablePositionedList), findsNothing);
  });
}