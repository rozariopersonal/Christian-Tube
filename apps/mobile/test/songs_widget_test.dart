import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/songs/models/song.dart';
import 'package:mobile/features/songs/screens/song_reader_screen.dart';
import 'package:mobile/features/songs/screens/songs_library_screen.dart';
import 'package:mobile/features/songs/adapters/song_catalog_adapter.dart';
import 'package:mobile/features/songs/services/songs_catalog_service.dart';
import 'package:mobile/features/songs/widgets/song_card.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.dark],
    );

Song _song({
  required String id,
  required String title,
  String? titleRoman,
  String? author,
  String? album,
  String? collection,
  String language = 'en',
  List<String> verses = const ['Verse one line one\nVerse one line two',
                               'Verse two line one\nVerse two line two'],
  List<String> versesRoman = const [],
}) {
  return Song(
    id: id, title: title, titleRoman: titleRoman, author: author, album: album,
    collection: collection, language: language, verses: verses,
    versesRoman: versesRoman,
  );
}

class _FakeAdapter implements SongCatalogAdapter {
  final List<Song> songs;
  _FakeAdapter(this.songs);

  @override
  Future<List<Song>> fetchSongs({bool forceRefresh = false}) async => songs;

  @override
  Future<Song?> fetchSong(String songId, {bool forceRefresh = false}) async =>
      songs.where((s) => s.id == songId).firstOrNull;

  @override
  Future<List<Song>> search(String query, {int limit = 50}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    return songs.where((s) => s.matchesQuery(term)).take(limit).toList();
  }
}

const List<double> kBreakpoints = [320, 600, 840, 1400];

void main() {
  group('SongReaderScreen', () {
    final testSong = _song(
      id: 's1', title: 'Amazing Grace',
      author: 'John Newton', collection: 'Hymnal',
      language: 'en',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    for (final width in kBreakpoints) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: SongReaderScreen(initialSong: testSong),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Amazing Grace'), findsWidgets);
        expect(find.text('John Newton • Hymnal'), findsOneWidget);
        expect(find.text('Verse 1'), findsOneWidget);
        expect(find.text('Verse 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders transliteration when enabled and hides it by default',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      final tamilSong = _song(
        id: 'ta-141', title: 'எனக்காய் ஜீவன் விட்டவரே',
        titleRoman: 'Enakkaai Jeevan Vittavarae',
        language: 'ta',
        verses: const ['எனக்காய் ஜீவன் விட்டவரே\nஎன்னோடிருக்க எழுந்தவரே'],
        versesRoman: const ['Enakkaai jeevan vittavarae\nEnnodirukka ezhunthavarae'],
      );

      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongReaderScreen(initialSong: tamilSong),
      ));
      await tester.pumpAndSettle();

      // Default: Tamil script only, transliteration hidden.
      expect(find.text('எனக்காய் ஜீவன் விட்டவரே'), findsWidgets);
      expect(find.text('Enakkaai jeevan vittavarae\nEnnodirukka ezhunthavarae'), findsNothing);

      // Toggle on → transliteration appears.
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Enakkaai Jeevan Vittavarae'), findsWidgets);
      expect(find.text('Enakkaai jeevan vittavarae\nEnnodirukka ezhunthavarae'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a not-found state for an empty song', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: const SongReaderScreen(initialSong: Song.empty()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Song not found'), findsOneWidget);
      expect(find.text('Verse 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SongsLibraryScreen', () {
    final songs = [
      _song(id: 'a', title: 'Song A', author: 'Author1', album: 'Album1',
            collection: 'Col1', language: 'en'),
      _song(id: 'b', title: 'Song B', author: 'Author2', album: 'Album1',
            collection: 'Col2', language: 'en'),
      _song(id: 'c', title: 'Song C', author: 'Author1', album: 'Album2',
            collection: 'Col1', language: 'ta'),
    ];

    SongsCatalogService fakeService() => SongsCatalogService(
      adapter: _FakeAdapter(songs),
    );

    for (final width in kBreakpoints) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(MaterialApp(
          theme: testTheme(),
          home: SongsLibraryScreen(service: fakeService()),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Songs'), findsWidgets);
        expect(find.text('Song A'), findsOneWidget);
        expect(find.text('Song B'), findsOneWidget);
        expect(find.text('Song C'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows segmented control and group headers',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      // Album grouping is default
      expect(find.text('Album1'), findsOneWidget);
      expect(find.text('Album2'), findsOneWidget);
      expect(find.text('Songs'), findsWidgets);
    });

    testWidgets('groups by author after switching', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      // Tap the Authors segment button
      await tester.tap(find.text('Authors'));
      await tester.pumpAndSettle();

      expect(find.text('Author1'), findsOneWidget);
      expect(find.text('Author2'), findsOneWidget);
    });

    testWidgets('search field filters the list', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Song A');
      await tester.pumpAndSettle();

      expect(find.byType(SongCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SongCard),
          matching: find.text('Song A'),
        ),
        findsOneWidget,
      );
      expect(find.text('Song B'), findsNothing);
      expect(find.text('Song C'), findsNothing);
    });

    testWidgets('search matches an author and clears back to full list',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Author2');
      await tester.pumpAndSettle();

      expect(find.text('Song B'), findsOneWidget);
      expect(find.text('Song A'), findsNothing);

      // Clear via the suffix button restores the full grouped list.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Song A'), findsOneWidget);
      expect(find.text('Song B'), findsOneWidget);
      expect(find.text('Song C'), findsOneWidget);
    });

    testWidgets('search shows an empty state when nothing matches',
        (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('No songs found'), findsOneWidget);
      expect(find.text('Song A'), findsNothing);
    });

    testWidgets('songs render as list rows, not grid tiles', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SliverGrid), findsNothing);
      expect(find.byType(SliverList), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the offline download action on native', (tester) async {
      setSurfaceSize(tester, 400, 800);
      await tester.pumpWidget(MaterialApp(
        theme: testTheme(),
        home: SongsLibraryScreen(service: fakeService()),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
