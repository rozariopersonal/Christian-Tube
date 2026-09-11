import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';
import 'package:mobile/features/articles/screens/wftw_teachings_screen.dart';
import 'package:mobile/features/articles/widgets/wftw_shelf.dart';
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

List<WftwIndexEntry> sampleEntries() => const [
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
        id: '2026_08_30',
        title: 'Seek the Gifts of the Spirit to Serve Others',
        date: '2026-08-30',
        year: 2026,
      ),
      WftwIndexEntry(
        id: '2001_01_07',
        title: 'Three Marks Of A Spiritual Man',
        date: '2001-01-07',
        year: 2001,
      ),
      WftwIndexEntry(
        id: '2026_09_06',
        title: 'A Tamil Teaching (தமிழ்)',
        date: '2026-09-06',
        year: 2026,
        lang: 'ta',
      ),
    ];

const List<double> kBreakpoints = [320, 600, 840, 1400];

class _ArticleStub extends StatelessWidget {
  final String? expectedLang;
  const _ArticleStub({this.expectedLang});

  @override
  Widget build(BuildContext context) {
    if (expectedLang != null && expectedLang != 'en' && expectedLang != 'ta') {
      throw StateError('unexpected lang $expectedLang');
    }
    return const Scaffold(body: Text('article-stub'));
  }
}

void main() {
  group('WftwTeachingsScreen', () {
    for (final width in kBreakpoints) {
      testWidgets('renders combined multi-language entries without overflow '
          'at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: WftwTeachingsScreen(loader: () async => sampleEntries()),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Word for the Week'), findsOneWidget);
        expect(find.text('4 teachings • All'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('2001'), findsOneWidget);
        expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
        expect(find.text('A Tamil Teaching (தமிழ்)'), findsOneWidget);
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
        home: WftwTeachingsScreen(
          loader: () async => sampleEntries(),
          langController: lang,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 teaching • Tamil'), findsOneWidget);
      expect(find.text('A Tamil Teaching (தமிழ்)'), findsOneWidget);
      expect(find.text('Few Will Find the Narrow Way'), findsNothing);
    });

    testWidgets('shows a helpful empty message when language has no teachings',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final lang = LibraryLanguagesController()
        ..selectLanguages({'de'});
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: WftwTeachingsScreen(
          loader: () async => sampleEntries(),
          langController: lang,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('No teachings available in the selected languages.'),
        findsOneWidget,
      );
    });

    testWidgets('search filters rows across years', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: WftwTeachingsScreen(loader: () async => sampleEntries()),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'gifts');
      await tester.pumpAndSettle();

      expect(find.text('Seek the Gifts of the Spirit to Serve Others'), findsOneWidget);
      expect(find.text('Few Will Find the Narrow Way'), findsNothing);
      expect(find.text('2001'), findsNothing);
    });

    testWidgets('clears search via suffix icon', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: WftwTeachingsScreen(loader: () async => sampleEntries()),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz nonmatch');
      await tester.pumpAndSettle();
      expect(find.text('No teachings match "zzz nonmatch".'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
    });

    testWidgets('shows retry on failure then loads on tap', (tester) async {
      setSurfaceSize(tester, 400, 800);
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: WftwTeachingsScreen(loader: () async {
          calls++;
          if (calls == 1) throw Exception('network down');
          return sampleEntries();
        }),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Could not load Word for the Week teachings.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
    });

    testWidgets('tapping an English row routes to the article route',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final router = GoRouter(
        initialLocation: '/teachings',
        routes: [
          GoRoute(
            path: '/teachings',
            builder: (_, __) =>
                WftwTeachingsScreen(loader: () async => sampleEntries()),
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: router, theme: testTheme()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Few Will Find the Narrow Way'));
      await tester.pumpAndSettle();
      expect(find.byType(_ArticleStub), findsOneWidget);
    });

    testWidgets('tapping a non-English row routes with its language',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final router = GoRouter(
        initialLocation: '/teachings',
        routes: [
          GoRoute(
            path: '/teachings',
            builder: (_, __) =>
                WftwTeachingsScreen(loader: () async => sampleEntries()),
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: router, theme: testTheme()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A Tamil Teaching (தமிழ்)'));
      await tester.pumpAndSettle();
      expect(find.byType(_ArticleStub), findsOneWidget);
    });
  });

  group('WftwShelf', () {
    for (final width in kBreakpoints) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        var viewAllTapped = false;
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: Scaffold(
            body: WftwShelf(
              entries: sampleEntries(),
              onViewAll: () => viewAllTapped = true,
              onTapArticle: (_) {},
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Word for the Week'), findsOneWidget);
        expect(find.text('View all'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('View all'));
        expect(viewAllTapped, isTrue);
      });
    }

    testWidgets('tile tap invokes article callback', (tester) async {
      setSurfaceSize(tester, 400, 800);
      WftwIndexEntry? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: WftwShelf(
            entries: sampleEntries(),
            onViewAll: () {},
            onTapArticle: (e) => tapped = e,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Few Will Find the Narrow Way'));
      expect(tapped?.id, '2026_09_06');
    });
  });
}