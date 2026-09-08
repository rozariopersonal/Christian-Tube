import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/features/songs/adapters/song_catalog_adapter.dart';
import 'package:mobile/features/songs/controllers/songs_library_controller.dart';
import 'package:mobile/features/songs/models/song.dart';
import 'package:mobile/features/songs/services/songs_catalog_service.dart';
import 'package:mobile/shared/services/library_languages_controller.dart';

class _FakeCatalogAdapter implements SongCatalogAdapter {
  final List<Song> songs;
  bool shouldFail = false;

  _FakeCatalogAdapter(this.songs);

  @override
  Future<List<Song>> fetchSongs({bool forceRefresh = false}) async {
    if (shouldFail) throw Exception('network');
    return songs;
  }

  @override
  Future<Song?> fetchSong(String songId, {bool forceRefresh = false}) async {
    for (final s in songs) {
      if (s.id == songId) return s;
    }
    return null;
  }
}

Song _song({
  required String id,
  required String title,
  String? author,
  String? album,
  String? collection,
  String language = 'en',
  List<String> verses = const ['Line one\nLine two'],
}) {
  return Song(
    id: id,
    title: title,
    author: author,
    album: album,
    collection: collection,
    language: language,
    verses: verses,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Song model', () {
    test('round-trips through JSON', () {
      final song = _song(
        id: 's1',
        title: 'Amazing Grace',
        author: 'John Newton',
        album: 'Hymns',
        collection: 'Classic',
        language: 'en',
        verses: ['Amazing grace\nhow sweet',
                  'That saved a wretch like me'],
      );
      final decoded = Song.fromJson(song.toJson());
      expect(decoded.id, 's1');
      expect(decoded.title, 'Amazing Grace');
      expect(decoded.author, 'John Newton');
      expect(decoded.album, 'Hymns');
      expect(decoded.collection, 'Classic');
      expect(decoded.language, 'en');
      expect(decoded.verses.length, 2);
      expect(decoded.audioUrl, isNull);
    });

    test('fromJson defaults missing fields', () {
      final decoded = Song.fromJson(const {'id': 'x', 'title': 'T'});
      expect(decoded.language, 'en');
      expect(decoded.verses, isEmpty);
      expect(decoded.author, isNull);
    });

    test('empty assigns default language', () {
      const empty = Song.empty();
      expect(empty.id, '');
      expect(empty.language, 'en');
    });

    test('round-trips optional transliteration fields', () {
      final song = _song(
        id: 'ta-1',
        title: 'எனக்காய் ஜீவன் விட்டவரே',
        author: 'சிலுவை',
        language: 'ta',
        verses: const ['தமிழ் வரி ஒன்று', 'தமிழ் வரி இரண்டு'],
      );
      final withTranslit = Song(
        id: song.id,
        title: song.title,
        titleRoman: 'Enakkaai Jeevan Vittavarae',
        author: song.author,
        language: song.language,
        verses: song.verses,
        versesRoman: const ['Tamil line one', 'Tamil line two'],
      );

      final decoded = Song.fromJson(withTranslit.toJson());
      expect(decoded.titleRoman, 'Enakkaai Jeevan Vittavarae');
      expect(decoded.versesRoman, const ['Tamil line one', 'Tamil line two']);
      expect(decoded.hasTransliteration, isTrue);
    });

    test('songs without transliteration report hasTransliteration false', () {
      final plain = _song(id: 's1', title: 'A');
      const withEmptyRoman = Song(
        id: 's2',
        title: 'B',
        language: 'ta',
        verses: ['வரி'],
        versesRoman: [''],
      );
      expect(plain.hasTransliteration, isFalse);
      expect(withEmptyRoman.hasTransliteration, isFalse);
    });
  });

  group('SongsLibraryController', () {
    test('loads songs and groups by album', () async {
      final controller = SongsLibraryController(
        service: SongsCatalogService(
          adapter: _FakeCatalogAdapter([
            _song(id: 'a', title: 'A', author: 'X', album: 'One'),
            _song(id: 'b', title: 'B', author: 'X', album: 'One'),
            _song(id: 'c', title: 'C', author: 'Y', album: 'Two'),
          ]),
        ),
      );
      // Give the async load a tick.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.songs.length, 3);
      expect(controller.filteredSongs.length, 3);

      final groups = controller.groupedSongs;
      expect(groups.length, 2);
      expect(groups.map((g) => g.label), containsAll(['One', 'Two']));
      final one = groups.firstWhere((g) => g.label == 'One');
      expect(one.songs.length, 2);
      expect(one.subtitle, 'X');
      controller.dispose();
    });

    test('album grouping subtitle keeps the first song author, not the last',
        () async {
      final controller = SongsLibraryController(
        service: SongsCatalogService(
          adapter: _FakeCatalogAdapter([
            _song(id: 'a', title: 'A', author: 'Zed', album: 'One'),
            _song(id: 'b', title: 'B', author: 'Amy', album: 'One'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final groups = controller.groupedSongs;
      final one = groups.firstWhere((g) => g.label == 'One');
      // First song's author, not the last-processed song.
      expect(one.subtitle, 'Zed');
      controller.dispose();
    });

    test('groups by author', () async {
      final controller = SongsLibraryController(
        service: SongsCatalogService(
          adapter: _FakeCatalogAdapter([
            _song(id: 'a', title: 'A', author: 'X', album: 'One'),
            _song(id: 'b', title: 'B', author: 'Y', album: 'One'),
            _song(id: 'c', title: 'C', author: 'X', album: 'Two'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.setGroupMode(SongGroupMode.authors);
      final groups = controller.groupedSongs;
      expect(groups.map((g) => g.label), containsAll(['X', 'Y']));
      final x = groups.firstWhere((g) => g.label == 'X');
      expect(x.songs.length, 2);
      controller.dispose();
    });

    test('filters songs by the global language selection', () async {
      final lang = LibraryLanguagesController();
      lang.announceLanguages(['en', 'ta']);

      final controller = SongsLibraryController(
        service: SongsCatalogService(
          adapter: _FakeCatalogAdapter([
            _song(id: 'a', title: 'A', language: 'en'),
            _song(id: 'b', title: 'B', language: 'ta'),
            _song(id: 'c', title: 'C', language: 'ta'),
          ]),
        ),
        langController: lang,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.filteredSongs.length, 3, reason: 'all selected by default');

      await lang.selectLanguages({'ta'});
      // Language change notifies listeners synchronously after selectLanguages.
      expect(controller.filteredSongs.length, 2);
      expect(controller.filteredSongs.every((s) => s.language == 'ta'), isTrue);

      await lang.selectLanguages({'en'});
      expect(controller.filteredSongs.length, 1);
      controller.dispose();
      lang.dispose();
    });

    test('handles a failing load by keeping empty state', () async {
      final adapter = _FakeCatalogAdapter([
        _song(id: 'a', title: 'A'),
      ]);
      adapter.shouldFail = true;
      final controller = SongsLibraryController(
        service: SongsCatalogService(adapter: adapter),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.songs, isEmpty);
      controller.dispose();
    });

    test('self-owns a language controller when none is injected and filters',
        () async {
      SharedPreferences.setMockInitialValues({});
      final controller = SongsLibraryController(
        service: SongsCatalogService(
          adapter: _FakeCatalogAdapter([
            _song(id: 'a', title: 'A', language: 'en'),
            _song(id: 'b', title: 'B', language: 'ta'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // The self-owned controller announces the songs' languages.
      final available = controller.languageController.state.availableLanguages
          .map((l) => l.toLowerCase())
          .toSet();
      expect(available, containsAll(['all', 'en', 'ta']));

      // Selecting a language on the shared controller filters songs.
      await controller.languageController.selectLanguages({'ta'});
      expect(controller.filteredSongs.length, 1);
      expect(controller.filteredSongs.first.id, 'b');
      controller.dispose();
    });
  });
}
