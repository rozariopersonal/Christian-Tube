import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';
import 'package:mobile/features/articles/screens/wftw_teachings_screen.dart';
import 'package:mobile/features/articles/widgets/wftw_shelf.dart';

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
    ];

const List<double> kBreakpoints = [320, 600, 840, 1400];

class _ArticleStub extends StatelessWidget {
  const _ArticleStub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('article-stub'));
}

void main() {
  group('WftwTeachingsScreen', () {
    for (final width in kBreakpoints) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: WftwTeachingsScreen(loader: () async => sampleEntries()),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Word for the Week'), findsOneWidget);
        expect(find.text('3 teachings • Zac Poonen'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('2001'), findsOneWidget);
        expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

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

    testWidgets('tapping a row navigates to the article route', (tester) async {
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
            builder: (_, state) => const _ArticleStub(),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router, theme: testTheme()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Few Will Find the Narrow Way'));
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