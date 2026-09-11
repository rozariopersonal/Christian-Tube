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
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) async => series;
}

class _FakeStorageService extends AudioStorageService {
  @override
  Future<AudioTrack?> getLastTrack() async => null;

  @override
  Future<int> getPosition(String trackId) async => 0;
}

AudioSeries _series(
  String id,
  String title, {
  String speaker = 'Zac Poonen',
  String category = 'Verse By Verse',
  String language = 'en',
  String description = '',
}) {
  return AudioSeries(
    id: id,
    title: title,
    description: description,
    speaker: speaker,
    coverUrl: null,
    trackCount: 5,
    category: category,
    language: language,
    tracks: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AudioLibraryController Search and Grouping Tests', () {
    test('instant search filters by title, speaker, and category', () async {
      final sampleSeries = [
        _series('1', 'Romans Exposition', speaker: 'Zac Poonen', category: 'Verse By Verse'),
        _series('2', 'Foundations of Faith', speaker: 'Ian Thomas', category: 'Foundations'),
        _series('3', 'Holy Living in Babylon', speaker: 'Zac Poonen', category: 'Christian Living'),
      ];

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService(sampleSeries),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.state.filteredSeries.length, 3);
      expect(controller.state.isSearching, isFalse);

      // Search by title
      controller.setSearchQuery('Romans');
      expect(controller.state.isSearching, isTrue);
      expect(controller.state.searchResults.length, 1);
      expect(controller.state.searchResults.first.title, 'Romans Exposition');

      // Search by speaker
      controller.setSearchQuery('Ian Thomas');
      expect(controller.state.searchResults.length, 1);
      expect(controller.state.searchResults.first.speaker, 'Ian Thomas');

      // Search by category
      controller.setSearchQuery('Christian Living');
      expect(controller.state.searchResults.length, 1);
      expect(controller.state.searchResults.first.title, 'Holy Living in Babylon');

      // Clear search
      controller.clearSearch();
      expect(controller.state.isSearching, isFalse);
      expect(controller.state.searchResults.length, 3);

      controller.dispose();
    });

    test('grouping by category, speaker, and alphabetical produces correct maps', () async {
      final sampleSeries = [
        _series('1', 'Romans Exposition', speaker: 'Zac Poonen', category: 'Verse By Verse'),
        _series('2', 'Genesis Survey', speaker: 'Zac Poonen', category: 'Verse By Verse'),
        _series('3', 'Foundations of Faith', speaker: 'Ian Thomas', category: 'Foundations'),
        _series('4', 'Abundant Life', speaker: 'Ian Thomas', category: 'Christian Living'),
      ];

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService(sampleSeries),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Category grouping
      final byCat = controller.state.seriesByCategory;
      expect(byCat['Verse By Verse']?.length, 2);
      expect(byCat['Foundations']?.length, 1);
      expect(byCat['Christian Living']?.length, 1);

      // Speaker grouping
      final bySpeaker = controller.state.seriesBySpeaker;
      expect(bySpeaker['Zac Poonen']?.length, 2);
      expect(bySpeaker['Ian Thomas']?.length, 2);

      // Alphabetical grouping
      final byAlpha = controller.state.seriesAlphabetical;
      expect(byAlpha['A']?.length, 1); // Abundant Life
      expect(byAlpha['F']?.length, 1); // Foundations of Faith
      expect(byAlpha['G']?.length, 1); // Genesis Survey
      expect(byAlpha['R']?.length, 1); // Romans Exposition

      controller.dispose();
    });

    test('view mode switching updates state', () async {
      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
      );

      expect(controller.state.viewMode, AudioViewMode.featured);

      controller.setViewMode(AudioViewMode.byCategory);
      expect(controller.state.viewMode, AudioViewMode.byCategory);

      controller.setViewMode(AudioViewMode.bySpeaker);
      expect(controller.state.viewMode, AudioViewMode.bySpeaker);

      controller.setViewMode(AudioViewMode.alphabetical);
      expect(controller.state.viewMode, AudioViewMode.alphabetical);

      controller.dispose();
    });
  });
}
