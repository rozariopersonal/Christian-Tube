import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/article_data.dart';
import 'package:mobile/features/articles/screens/article_reader_screen.dart';
import 'package:mobile/features/articles/services/article_sync_service.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/shared/ui/floating_selection_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Articles implements ArticleSyncService {
  @override
  Future<ArticleData?> getArticle(String articleId, {String? lang}) async =>
      const ArticleData(
        id: 'article1',
        title: 'Example',
        author: 'Author',
        date: '2024-01-01',
        lines: [
          ArticleLine(line: 0, text: 'Grace'),
          ArticleLine(line: 1, text: 'Grace')
        ],
      );
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BookService.instance.overrideDbPath = inMemoryDatabasePath;
    await BookService.instance.initialize();
  });
  testWidgets('highlight saves only the selected repeated article line',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home:
          ArticleReaderScreen(articleId: 'article1', syncService: _Articles()),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Grace').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloatingSelectionBar.swatchKey(0)));
    await tester.pumpAndSettle();
    final highlights = await tester.runAsync(
        () => BookService.instance.getHighlightsForBook('article_article1_en'));
    expect(highlights, hasLength(1));
    expect(highlights!.single.pageNumber, 2);
    expect(highlights.single.startChar, 0);
    expect(highlights.single.endChar, 5);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home:
          ArticleReaderScreen(articleId: 'article1', syncService: _Articles()),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final lines = tester.widgetList<Text>(find.text('Grace')).toList();
    final first = lines[0].textSpan as TextSpan;
    final second = lines[1].textSpan as TextSpan;
    expect((first.children!.first as TextSpan).style?.backgroundColor, isNull);
    expect(
        (second.children!.first as TextSpan).style?.backgroundColor, isNotNull);
  });
}
