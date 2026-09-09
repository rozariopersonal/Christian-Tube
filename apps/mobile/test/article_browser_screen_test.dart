import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';
import 'package:mobile/features/articles/screens/article_browser_screen.dart';
import 'package:mobile/shared/services/library_languages_controller.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.dark],
    );

const List<WftwIndexEntry> sampleCombined = [
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
  WftwIndexEntry(
    id: '2025_01_05',
    title: 'Tamil old devotion',
    date: '2025-01-05',
    year: 2025,
    lang: 'ta',
  ),
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
      testWidgets('renders combined entries without overflow at ${width}px',
          (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: ArticleBrowserScreen(loader: () async => sampleCombined),
        ));
        await tester.pumpAndSettle();

        expect(find.text('3 articles • All'), findsOneWidget);
        expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
        expect(find.text('Tamil old devotion'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('2001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('honors shared library language filter (Tamil only)',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final lang = LibraryLanguagesController()
        ..selectLanguages({'ta'});
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: ArticleBrowserScreen(
          loader: () async => sampleCombined,
          langController: lang,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 articles • Tamil'), findsOneWidget);
      expect(find.text('Tamil old devotion'), findsOneWidget);
      expect(find.text('Few Will Find the Narrow Way'), findsNothing);
    });

    testWidgets('search filters rows in the current language', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: ArticleBrowserScreen(loader: () async => sampleCombined),
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
        home: ArticleBrowserScreen(loader: () async {
          calls++;
          if (calls == 1) throw Exception('network down');
          return sampleCombined;
        }),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Could not load articles.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
    });

    testWidgets('tapping a non-English row routes to /article/:id with its lang',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final router = GoRouter(
        initialLocation: '/articles',
        routes: [
          GoRoute(
            path: '/articles',
            builder: (_, __) =>
                ArticleBrowserScreen(loader: () async => sampleCombined),
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
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: router, theme: testTheme()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tamil old devotion'));
      await tester.pumpAndSettle();
      expect(find.byType(_ArticleStub), findsOneWidget);
    });
  });
}
