import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/models/wftw_index_entry.dart';
import 'package:mobile/features/articles/services/wftw_index_service.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';
import 'package:mobile/features/library/screens/library_screen.dart';
import 'package:mobile/features/library/services/library_data_loader.dart';
import 'package:mobile/features/songs/models/song.dart';

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

const List<WftwIndexEntry> sampleArticles = [
  WftwIndexEntry(
    id: '2026_09_06',
    title: 'The Narrow Way (Tamil teaching)',
    date: '2026-09-06',
    year: 2026,
    lang: 'ta',
  ),
  WftwIndexEntry(
    id: '2026_08_30',
    title: 'German devotion',
    date: '2026-08-30',
    year: 2026,
    lang: 'de',
  ),
];

const List<ArticleLanguage> sampleLanguages = [
  ArticleLanguage(code: 'en', name: 'English', count: 3),
  ArticleLanguage(code: 'ta', name: 'Tamil', count: 2),
  ArticleLanguage(code: 'de', name: 'Deutsch', count: 1),
];

const List<double> kBreakpoints = [320, 600, 840, 1400];

Widget buildLibrary({
  LibraryDataLoader? loader,
  Future<List<WftwIndexEntry>> Function()? articlesLoader,
  Future<List<ArticleLanguage>> Function()? languagesLoader,
  Future<List<Song>> Function()? songsLoader,
}) {
  return MaterialApp(
    theme: testTheme(),
    home: LibraryScreen(
      loader: loader,
      articlesLoader: articlesLoader,
      languagesLoader: languagesLoader,
      songsLoader: songsLoader,
    ),
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
          articlesLoader: () async => sampleArticles,
          languagesLoader: () async => sampleLanguages,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Library'), findsOneWidget);
        expect(find.text('Books'), findsOneWidget);
        expect(find.text('A Heavenly Home'), findsOneWidget);
        expect(find.text('Articles'), findsOneWidget);
        expect(find.text('The Narrow Way (Tamil teaching)'), findsOneWidget);
        expect(find.text('Tamil'), findsNWidgets(2));
        expect(find.text('View all'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows browse card when no reading progress exists',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(buildLibrary(
        loader: _FakeLoader(books: [book('b1', 'First Book')], progress: const []),
        articlesLoader: () async => sampleArticles,
        languagesLoader: () async => sampleLanguages,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Explore the Books library'), findsOneWidget);
      expect(find.text('A Heavenly Home'), findsNothing);
    });

    testWidgets('hides articles shelf when combined index fails to load',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(buildLibrary(
        loader: loaderWithData(),
        articlesLoader: () async => throw Exception('offline'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A Heavenly Home'), findsOneWidget);
      expect(find.text('Articles'), findsNothing);
      expect(find.text('Tamil'), findsNothing);
      expect(find.text('Word for the Week'), findsNothing);
    });

    testWidgets('catalog languages outside the registry render as names',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(buildLibrary(
        loader: loaderWithData(),
        articlesLoader: () async => sampleArticles,
        languagesLoader: () async => [
          ...sampleLanguages,
          const ArticleLanguage(code: 'gu', name: 'Gujarati', count: 1),
        ],
        songsLoader: () async => const [
          Song(id: 's1', title: 'S', language: 'gu', verses: ['x']),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('All Languages'), findsOneWidget);
      await tester.tap(find.text('All Languages'));
      await tester.pumpAndSettle();

      // The registered language shows its name, never a raw ISO code, as the
      // chooseable label; the code glyph stays only in the decorative badge
      // (same convention as 'TA' / 'HI' in the badge box).
      expect(find.text('Gujarati'), findsWidgets);
      expect(find.text('gu'), findsNothing);
      expect(find.text('GU'), findsOneWidget);
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
          GoRoute(
              path: '/articles',
              builder: (_, __) => const _Dest(body: 'articles-dest')),
          GoRoute(
            path: '/article/:id',
            builder: (_, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final lang = state.uri.queryParameters['lang'] ??
                  extra?['lang'] as String? ??
                  'en';
              return _Dest(
                body:
                    'article-${state.pathParameters['id']}-lang-$lang',
              );
            },
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

      await tester.tap(find.text('View all').at(0));
      await tester.pumpAndSettle();
      expect(find.text('books-dest'), findsOneWidget);
    });

    testWidgets('Articles View all routes to /articles', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: buildRouter(),
        theme: testTheme(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View all').at(1));
      await tester.pumpAndSettle();
      expect(find.text('articles-dest'), findsOneWidget);
    });

    testWidgets('tapping a non-English article tile carries its language',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: buildRouter(),
        theme: testTheme(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('The Narrow Way (Tamil teaching)'));
      await tester.pumpAndSettle();
      expect(find.text('article-2026_09_06-lang-ta'), findsOneWidget);
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
      articlesLoader: _nullArticles,
      languagesLoader: _loadLanguages,
    );
  }
}

Future<List<WftwIndexEntry>> _nullArticles() async => sampleArticles;
Future<List<ArticleLanguage>> _loadLanguages() async => sampleLanguages;

class _Dest extends StatelessWidget {
  final String body;
  const _Dest({required this.body});
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(body));
}