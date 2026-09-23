import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/article_data.dart';
import 'package:mobile/features/articles/screens/article_reader_screen.dart';
import 'package:mobile/features/articles/services/article_sync_service.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineSyncService implements ArticleSyncService {
  @override
  Future<ArticleData?> getArticle(String articleId, {String? lang}) async {
    throw Exception('offline');
  }
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

class _ArticlesBrowserStub extends StatelessWidget {
  const _ArticlesBrowserStub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ARTICLES_BROWSER'),
            TextButton(
              onPressed: () => context.push('/article/2024_10_26'),
              child: const Text('OPEN_ARTICLE'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the production route table: `/articles` lives inside the navigation
/// shell while `/article/:id` is a top-level route above it.
GoRouter buildRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/articles',
            builder: (context, state) => const _ArticlesBrowserStub(),
          ),
        ],
      ),
      GoRoute(
        path: '/article/:id',
        builder: (context, state) => ArticleReaderScreen(
          articleId: state.pathParameters['id'] ?? '',
          syncService: _OfflineSyncService(),
        ),
      ),
    ],
  );
}

Widget app(GoRouter router) => MaterialApp.router(
      theme: testTheme(),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'system back on a cold article deep link lands on the articles '
      'browser instead of exiting the app', (tester) async {
    await tester.pumpWidget(app(buildRouter('/article/2024_10_26')));
    await tester.pumpAndSettle();

    expect(find.byType(ArticleReaderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue,
        reason: 'back must be intercepted by PopScope, not bubble to '
            'SystemNavigator.pop (app exit)');
    await tester.pumpAndSettle();

    expect(find.byType(ArticleReaderScreen), findsNothing);
    expect(find.text('ARTICLES_BROWSER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'system back from a pushed article returns to the articles browser',
      (tester) async {
    await tester.pumpWidget(app(buildRouter('/articles')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN_ARTICLE'));
    await tester.pumpAndSettle();

    expect(find.byType(ArticleReaderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();

    expect(find.byType(ArticleReaderScreen), findsNothing);
    expect(find.text('ARTICLES_BROWSER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}