import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/screens/book_reader_screen.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/shared/ui/floating_selection_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const lineText =
    'Grace Grace Grace Grace Grace Grace Grace Grace Grace Grace Grace Grace';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BookService.instance.overrideDbPath = inMemoryDatabasePath;
    await BookService.instance.initialize();
    final db = await BookService.instance.database as Database;
    await db.insert('books', {
      'id': 'test-book',
      'title': 'Book',
      'author': 'Author',
      'total_pages': 1,
      'total_lines': 2,
      'created_at': ''
    });
    await db.insert('book_chapters', {
      'book_id': 'test-book',
      'chapter_index': 1,
      'chapter_title': 'One',
      'start_page': 1,
      'start_line': 1,
      'end_page': 1,
      'end_line': 2
    });
    for (var i = 1; i <= 2; i++) {
      await db.insert('book_content', {
        'book_id': 'test-book',
        'page_number': 1,
        'line_number': i,
        'chapter_index': 1,
        'content_type': 'p',
        'text': lineText
      });
    }
  });
  testWidgets('continuous selection highlights the selected source line',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: const BookReaderScreen(bookId: 'test-book')));
    for (var i = 0; i < 15 && find.text(lineText).evaluate().length < 2; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(lineText), findsNWidgets(2));
    await tester.pumpAndSettle();
    await tester.longPress(find.text(lineText).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloatingSelectionBar.swatchKey(0)));
    await tester.pumpAndSettle();
    List<dynamic>? highlights;
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      highlights = await tester.runAsync(
          () => BookService.instance.getHighlightsForBook('test-book'));
      if (highlights!.isNotEmpty) break;
    }
    expect(highlights, hasLength(1));
    expect(highlights!.single.id, startsWith('book_range_2_'));
    expect(highlights.single.text, 'Grace');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home:
            const BookReaderScreen(bookId: 'test-book', useContinuous: false)));
    for (var i = 0;
        i < 20 && find.text('$lineText $lineText').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('$lineText $lineText'), findsOneWidget);
    final paragraph = tester.widget<Text>(find.text('$lineText $lineText'));
    final spans = (paragraph.textSpan as TextSpan).children!.cast<TextSpan>();
    expect(
        spans
            .where((s) => s.style?.backgroundColor != null)
            .map((s) => s.text)
            .join(),
        'Grace');
    expect(spans.first.style?.backgroundColor, isNull);
  });
}
