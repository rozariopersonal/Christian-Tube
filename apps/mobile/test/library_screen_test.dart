import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';
import 'package:mobile/features/library/screens/library_screen.dart';
import 'package:mobile/features/library/services/library_data_loader.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.dark],
    );

class _FakeLoader implements LibraryDataLoader {
  final List<Book> books;
  final List<UserReadingProgress> progress;

  _FakeLoader({required this.books, required this.progress});

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Book>> getBooks() async => books;

  @override
  Future<List<UserReadingProgress>> getRecentProgress({int? limit}) async =>
      progress;
}

Book book(String id, String title) => Book(
      id: id,
      title: title,
      author: 'Zac Poonen',
      description: 'Sample book',
      coverFile: '${id}_cover.jpg',
      totalPages: 100,
      totalLines: 1000,
      createdAt: '2023-01-01',
    );

const List<WftwIndexEntry> sampleTeachings = [
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
];

const List<double> kBreakpoints = [320, 600, 840, 1400];

Widget buildLibrary({
  LibraryDataLoader? loader,
  Future<List<WftwIndexEntry>> Function()? wftwLoader,
}) {
  return MaterialApp(
    theme: testTheme(),
    home: LibraryScreen(loader: loader, wftwLoader: wftwLoader),
  );
}

void main() {
  group('LibraryScreen', () {
    LibraryDataLoader loaderWithData() => _FakeLoader(
          books: [
            book('a_heavenly_home', 'A Heavenly Home'),
            book('the_way_of_wisdom', 'The Way of Wisdom'),
          ],
          progress: const [
            UserReadingProgress(
              bookId: 'a_heavenly_home',
              currentPage: 12,
              currentLine: 3,
              completionPercent: 0.4,
              lastReadAt: '2026-09-01',
            ),
          ],
        );

    for (final width in kBreakpoints) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(buildLibrary(
          loader: loaderWithData(),
          wftwLoader: () async => sampleTeachings,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Library'), findsOneWidget);
        expect(find.text('Books'), findsOneWidget);
        expect(find.text('A Heavenly Home'), findsOneWidget);
        expect(find.text('Word for the Week'), findsOneWidget);
        expect(find.text('Few Will Find the Narrow Way'), findsOneWidget);
        expect(find.text('Articles'), findsOneWidget);
        expect(find.textContaining('coming soon'), findsOneWidget);
        expect(find.text('View all'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows browse card when no reading progress exists',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(buildLibrary(
        loader: _FakeLoader(books: [book('b1', 'First Book')], progress: const []),
        wftwLoader: () async => sampleTeachings,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Explore the Books library'), findsOneWidget);
      expect(find.text('A Heavenly Home'), findsNothing);
    });

    testWidgets('hides teaching shelf when index fails to load', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(buildLibrary(
        loader: loaderWithData(),
        wftwLoader: () async => throw Exception('offline'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Word for the Week'), findsNothing);
      expect(find.text('Articles'), findsOneWidget);
    });

    testWidgets('article placeholder tap shows coming-soon snackbar',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(buildLibrary(
        loader: loaderWithData(),
        wftwLoader: () async => sampleTeachings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Articles'));
      await tester.pump();
      expect(find.text('Articles are coming soon.'), findsOneWidget);
    });
  });

  GoRouter buildRouter() => GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(
          path: '/library',
          builder: (_, __) => const _RoutedLibrary(),
        ),
        GoRoute(path: '/books', builder: (_, __) => const _Dest(body: 'books-dest')),
        GoRoute(path: '/teachings', builder: (_, __) => const _Dest(body: 'teachings-dest')),
        GoRoute(
          path: '/article/:id',
          builder: (_, state) => _Dest(body: 'article-${state.pathParameters['id']}'),
        ),
      ],
    );

  group('LibraryScreen navigation', () {
    testWidgets('Books View all routes to /books', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: buildRouter(),
        theme: testTheme(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View all').first);
      await tester.pumpAndSettle();
      expect(find.text('books-dest'), findsOneWidget);
    });

    testWidgets('Word for the Week View all routes to /teachings',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: buildRouter(),
        theme: testTheme(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View all').last);
      await tester.pumpAndSettle();
      expect(find.text('teachings-dest'), findsOneWidget);
    });

    testWidgets('tapping a teaching shelf tile routes to the article',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: buildRouter(),
        theme: testTheme(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Few Will Find the Narrow Way'));
      await tester.pumpAndSettle();
      expect(find.text('article-2026_09_06'), findsOneWidget);
    });
  });
}

class _RoutedLibrary extends StatelessWidget {
  const _RoutedLibrary();

  @override
  Widget build(BuildContext context) {
    return LibraryScreen(
      loader: _FakeLoader(
        books: [book('a_heavenly_home', 'A Heavenly Home')],
        progress: const [
          UserReadingProgress(
            bookId: 'a_heavenly_home',
            currentPage: 2,
            currentLine: 1,
            completionPercent: 0.1,
            lastReadAt: '2026-09-01',
          ),
        ],
      ),
      wftwLoader: _nullWftw,
    );
  }
}

Future<List<WftwIndexEntry>> _nullWftw() async => sampleTeachings;

class _Dest extends StatelessWidget {
  final String body;
  const _Dest({required this.body});
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(body));
}
