import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';
import 'package:mobile/features/articles/screens/article_browser_screen.dart';
import 'package:mobile/features/articles/services/wftw_index_service.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.dark],
    );

const List<WftwIndexEntry> sampleEnglish = [
  WftwIndexEntry(
    id: '2026_09_06',
    title: 'Few Will Find the Narrow Way',
    date: '2026-09-06',
    year: 2026,
    bookNumber: 40,
    chapter: 7,
    startVerse: 13,
    endVerse: 14,
  ),
  WftwIndexEntry(
    id: '2001_01_07',
    title: 'Three Marks Of A Spiritual Man',
    date: '2001-01-07',
    year: 2001,
  ),
];

const List<WftwIndexEntry> sampleTamil = [
  WftwIndexEntry(
    id: '2026_09_06',
    title: 'Tamil Narrow Way teaching',
    date: '2026-09-06',
    year: 2026,
    lang: 'ta',
  ),
  WftwIndexEntry(
    id: '2025_01_05',
    title: 'Tamil old devotion',
    date: '2025-01-05',
    year: 2025,
    lang: 'ta',
  ),
];

const List<ArticleLanguage> sampleLanguages = [
  ArticleLanguage(code: 'en', name: 'English', count: 2),
  ArticleLanguage(code: 'ta', name: 'Tamil', count: 2),
];

const List<double> kBreakpoints = [320, 600, 840, 1400];

class _ArticleStub extends StatelessWidget {
  final String? expectedLang;
  const _ArticleStub({this.expectedLang});

  @override
  Widget build(BuildContext context) {
    if (expectedLang != null && expectedLang != 'ta') {
      throw StateError('unexpected lang $expectedLang');
    }
    return const Scaffold(body: Text('article-stub'));
  }
}

void main() {
  group('ArticleBrowserScreen', () {
    for (final width in kBreakpoints) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: ArticleBrowserScreen(
            loader: (_) async => sampleEnglish,
            languagesLoader: () async => sampleLanguages,
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('2 articles • English'), findsOneWidget);
        expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('2001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('switching language shows language chips and tagged rows',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      var requestedLang = '';
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: ArticleBrowserScreen(
          loader: (lang) async {
            requestedLang = lang;
            return sampleTamil;
          },
          languagesLoader: () async => sampleLanguages,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();

      expect(requestedLang, 'ta');
      expect(find.text('2 articles • Tamil'), findsOneWidget);
      expect(find.text('Tamil Narrow Way teaching'), findsOneWidget);
    });

    testWidgets('initialLang opens directly in that language', (tester) async {
      setSurfaceSize(tester, 400, 800);
      String? requested;
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: ArticleBrowserScreen(
          initialLang: 'ta',
          loader: (lang) async {
            requested = lang;
            return sampleTamil;
          },
          languagesLoader: () async => sampleLanguages,
        ),
      ));
      await tester.pumpAndSettle();

      expect(requested, 'ta');
      expect(find.text('2 articles • Tamil'), findsOneWidget);
    });

    testWidgets('search filters rows in the current language', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: ArticleBrowserScreen(
          loader: (_) async => sampleEnglish,
          languagesLoader: () async => sampleLanguages,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'spiritual');
      await tester.pumpAndSettle();

      expect(find.text('Three Marks Of A Spiritual Man'), findsOneWidget);
      expect(find.text('Few Will Find the Narrow Way'), findsNothing);
      expect(find.text('2001'), findsOneWidget);
    });

    testWidgets('shows retry on failure then loads on tap', (tester) async {
      setSurfaceSize(tester, 400, 800);
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: ArticleBrowserScreen(
          loader: (_) async {
            calls++;
            if (calls == 1) throw Exception('network down');
            return sampleEnglish;
          },
          languagesLoader: () async => sampleLanguages,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Could not load articles for English.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
    });

    testWidgets('tapping a row routes to /article/:id with its language',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final router = GoRouter(
        initialLocation: '/articles',
        routes: [
          GoRoute(
            path: '/articles',
            builder: (_, __) => ArticleBrowserScreen(
              loader: (_) async => sampleTamil,
              languagesLoader: () async => sampleLanguages,
              initialLang: 'ta',
            ),
          ),
          GoRoute(
            path: '/article/:id',
            builder: (_, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return _ArticleStub(
                expectedLang: state.uri.queryParameters['lang'] ??
                    extra?['lang'] as String? ??
                    'en',
              );
            },
          ),
        ],
      );
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: router, theme: testTheme()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tamil Narrow Way teaching'));
      await tester.pumpAndSettle();
      expect(find.byType(_ArticleStub), findsOneWidget);
    });
  });
}