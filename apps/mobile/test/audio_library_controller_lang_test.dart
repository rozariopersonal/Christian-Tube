import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/audio/controllers/audio_library_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/services/audio_catalog_service.dart';
import 'package:mobile/features/audio/services/audio_storage_service.dart';
import 'package:mobile/shared/services/library_languages_controller.dart';

class _FakeCatalogService extends AudioCatalogService {
  final List<AudioSeries> series;
  _FakeCatalogService(this.series);

  @override
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) async =>
      series;
}

class _FakeStorageService extends AudioStorageService {
  @override
  Future<AudioTrack?> getLastTrack() async => null;

  @override
  Future<int> getPosition(String trackId) async => 0;
}

AudioSeries _series(String id, String language, {String category = 'All'}) {
  return AudioSeries(
    id: id,
    title: 'Series $id',
    description: '',
    speaker: 'Zac Poonen',
    coverUrl: null,
    trackCount: 1,
    category: category,
    language: language,
    tracks: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioLibraryController language source of truth', () {
    setUp(() {
      // Start with no persisted selection so the default is 'All'.
      SharedPreferences.setMockInitialValues({});
    });

    test('announces its languages and filters by the shared selection',
        () async {
      final lang = LibraryLanguagesController();
      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([
          _series('en1', 'en'),
          _series('ta1', 'ta'),
        ]),
        storageService: _FakeStorageService(),
        langController: lang,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Audio languages are registered with the shared controller.
      final available = lang.state.availableLanguages
          .map((c) => c.toLowerCase())
          .toSet();
      expect(available, containsAll(['all', 'en', 'ta']));

      // Initially everything is selected.
      expect(controller.state.isAllLanguagesSelected, isTrue);
      expect(controller.state.filteredSeries.length, 2);

      // Selecting Tamil on the shared controller filters audio to Tamil.
      await lang.selectLanguages({'ta'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.selectedLanguages, {'ta'});
      expect(controller.state.filteredSeries.map((s) => s.id), ['ta1']);

      // The selection is a single global source of truth.
      expect(lang.state.selectedLanguages, {'ta'});

      controller.dispose();
      lang.dispose();
    });

    test('resetFilters resets the shared language selection to All', () async {
      final lang = LibraryLanguagesController();
      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([
          _series('en1', 'en'),
          _series('ta1', 'ta'),
        ]),
        storageService: _FakeStorageService(),
        langController: lang,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await lang.selectLanguages({'en'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.selectedLanguages, {'en'});

      controller.resetFilters();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.isAllLanguagesSelected, isTrue);
      expect(lang.state.isAllLanguages, isTrue);

      controller.dispose();
      lang.dispose();
    });
  });
}
