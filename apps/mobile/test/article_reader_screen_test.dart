import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/article_data.dart';
import 'package:mobile/features/articles/screens/article_reader_screen.dart';
import 'package:mobile/features/articles/services/article_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

class _OfflineSyncService implements ArticleSyncService {
  @override
  Future<ArticleData?> getArticle(String articleId, {String? lang}) async {
    throw Exception('offline');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final offlineService = _OfflineSyncService();

  Widget subject(String articleId, {String? initialTitle}) {
    return MaterialApp(
      theme: testTheme(),
      home: ArticleReaderScreen(
        articleId: articleId,
        initialTitle: initialTitle,
        syncService: offlineService,
      ),
    );
  }

  for (final width in [320.0, 600.0, 840.0, 1400.0]) {
    testWidgets('offline error state renders without overflow at $width '
        'logical px', (tester) async {
      setSurfaceSize(tester, width, 800);
      await tester.pumpWidget(subject('2024_10_26'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'overflow/exception at $width');
      expect(
        find.text('Connect to the internet to read this article.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  }

  testWidgets('shows the passed-in title in the app bar while loading',
      (tester) async {
    setSurfaceSize(tester, 320, 640);
    await tester.pumpWidget(subject('2024_10_26', initialTitle: 'Faith in Trials'));
    await tester.pump();

    expect(find.text('Faith in Trials'), findsOneWidget);
  });

  testWidgets(
      'tapping Retry re-attempts and stays in the offline error state',
      (tester) async {
    setSurfaceSize(tester, 320, 640);
    await tester.pumpWidget(subject('2024_10_26'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Connect to the internet to read this article.'),
      findsOneWidget,
    );
  });
}