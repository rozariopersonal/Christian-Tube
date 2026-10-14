import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/audio/controllers/audio_library_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/services/audio_catalog_service.dart';
import 'package:mobile/features/audio/services/audio_storage_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/shared/services/library_languages_controller.dart';

class _FakeChannelService extends ChannelService {
  _FakeChannelService(Set<String> initialNames)
      : names = Set.of(initialNames),
        ids = Set.of(initialNames),
        super.forTesting();

  Set<String> names;
  Set<String> ids;

  @override
  Set<String> get subscribedChannelNames => names;

  @override
  Set<String> get subscribedChannelIds => ids;

  @override
  Future<void> fetchChannels() async {}

  void setSubscription(Set<String> next) {
    names = Set.of(next);
    ids = Set.of(next);
    notifyListeners();
  }
}

class _FakeCatalogService extends AudioCatalogService {
  final List<AudioSeries> series;
  final List<AudioSeries> searchResults;
  bool? lastForceRefresh;
  int catalogCalls = 0;
  _FakeCatalogService(this.series, {List<AudioSeries>? searchResults})
      : searchResults = searchResults ?? series;

  @override
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) async {
    lastForceRefresh = forceRefresh;
    catalogCalls++;
    return series;
  }

  @override
  Future<List<AudioSeries>> search(String query) async => searchResults;
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

AudioSeries _youtubeSeries(
  String id,
  String title,
  int trackCount, {
  String category = 'YouTube',
  String language = 'en',
  DateTime? latestPublishedAt,
}) {
  return AudioSeries(
    id: id,
    title: title,
    description: '',
    speaker: 'Zac Poonen',
    coverUrl: null,
    trackCount: trackCount,
    category: category,
    language: language,
    latestPublishedAt: latestPublishedAt,
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

    test('forceRefresh propagates to the catalog service', () async {
      final sampleSeries = [
        _series('1', 'Romans Exposition'),
        _series('2', 'Genesis Survey'),
      ];

      final fake = _FakeCatalogService(sampleSeries);
      final controller = AudioLibraryController(
        catalogService: fake,
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
      );

      // Constructor fires a non-forced load.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fake.catalogCalls, greaterThanOrEqualTo(1));
      expect(fake.lastForceRefresh, isFalse);

      await controller.loadData(forceRefresh: true);

      expect(fake.lastForceRefresh, isTrue);
      expect(controller.state.seriesList.length, 2);

      controller.dispose();
    });
  });

  group('AudioLibraryController YouTube channel grid', () {
    test('async search results respect the active format filter', () async {
      final youtubeSeries = _youtubeSeries('yt1', 'CFC India Sermons', 40);
      final archiveSeries =
          _series('arch1', 'Romans Exposition', category: 'Bible Survey');
      final songsSeries = _youtubeSeries(
        'sg1',
        'Tamil Songs',
        500,
        category: 'Songs',
      );

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService(
          [youtubeSeries, archiveSeries, songsSeries],
          searchResults: [youtubeSeries, archiveSeries, songsSeries],
        ),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: _FakeChannelService({'CFC India Sermons'}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.selectFormat(AudioFormat.youtube);
      expect(controller.state.filteredSeries.map((s) => s.id), ['yt1']);

      // Deep async search on the YouTube tab must not surface Archive or
      // Songs series that the backend matched.
      controller.setSearchQuery('grace');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.state.searchResults.map((s) => s.id), ['yt1']);

      controller.dispose();
    });

    test('async search results respect the archive category filter', () async {
      final romans = _series('r1', 'Romans Exposition', category: 'Verse By Verse');
      final foundations = _series('f1', 'Foundations of Faith', category: 'Foundations');
      final songsSeries = _youtubeSeries('sg1', 'Tamil Songs', 10, category: 'Songs');

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService(
          [romans, foundations, songsSeries],
          searchResults: [romans, foundations, songsSeries],
        ),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.selectCategory('Foundations');
      controller.setSearchQuery('faith');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.state.searchResults.map((s) => s.id), ['f1']);

      controller.dispose();
    });

    test('channel grid sorts by most tracks by default and toggles to A-Z',
        () async {
      final a = _youtubeSeries('b', 'Beta Channel', 3);
      final c = _youtubeSeries('c', 'Alpha Channel', 50);
      final d = _youtubeSeries('d', 'Gamma Channel', 10);

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([a, c, d]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: _FakeChannelService({
          'Alpha Channel',
          'Beta Channel',
          'Gamma Channel',
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.selectFormat(AudioFormat.youtube);

      expect(controller.state.channelSort, AudioChannelSort.mostTracks);
      expect(controller.state.channelSortedSeries.map((s) => s.id),
          ['c', 'd', 'b']); // Alpha (50), Gamma (10), Beta (3)

      controller.setChannelSort(AudioChannelSort.name);
      expect(controller.state.channelSortedSeries.map((s) => s.id),
          ['c', 'b', 'd']); // Alpha, Beta, Gamma

      controller.dispose();
    });

    test('channel sort applies after language filtering', () async {
      final ta = _youtubeSeries('ta1', 'Tamil Channel', 8, language: 'ta');
      final enBig = _youtubeSeries('en1', 'English Channel', 90, language: 'en');
      final taBig = _youtubeSeries('ta2', 'Another Tamil Channel', 30, language: 'ta');

      final lang = LibraryLanguagesController();
      lang.announceLanguages(['en', 'ta']);

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([ta, enBig, taBig]),
        storageService: _FakeStorageService(),
        langController: lang,
        channelService: _FakeChannelService({
          'Tamil Channel',
          'English Channel',
          'Another Tamil Channel',
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.selectFormat(AudioFormat.youtube);
      lang.selectLanguages({'ta'});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.state.channelSortedSeries.map((s) => s.id),
          ['ta2', 'ta1']);

      controller.setChannelSort(AudioChannelSort.name);
      expect(controller.state.channelSortedSeries.map((s) => s.id),
          ['ta2', 'ta1']);

      controller.dispose();
    });

test('newest sort orders by recency, placing series without a date last',
        () async {
      final older = _youtubeSeries(
        'old',
        'Older Channel',
        5,
        latestPublishedAt: DateTime.utc(2025, 1, 1),
      );
      final newer = _youtubeSeries(
        'new',
        'Newer Channel',
        2,
        latestPublishedAt: DateTime.utc(2026, 9, 15),
      );
      final unknown = _youtubeSeries('na', 'No Date Channel', 50);

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([older, newer, unknown]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: _FakeChannelService({
          'Older Channel',
          'Newer Channel',
          'No Date Channel',
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.selectFormat(AudioFormat.youtube);

      controller.setChannelSort(AudioChannelSort.newest);
      expect(controller.state.channelSortedSeries.map((s) => s.id),
          ['new', 'old', 'na']); // recency desc, undated pushed last

      controller.dispose();
    });

    test('YouTube tab hides channels the user is not subscribed to', () async {
      final subscribed = _youtubeSeries('c', 'Alpha Channel', 50);
      final unsubscribed = _youtubeSeries('b', 'Beta Channel', 3);

      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([subscribed, unsubscribed]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: _FakeChannelService({'Alpha Channel'}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.selectFormat(AudioFormat.youtube);

      expect(controller.state.filteredSeries.map((s) => s.id), ['c']);
      expect(controller.state.hasChannelSubscriptions, isTrue);
      expect(controller.state.shouldShowSubscribedCta, isFalse);

      controller.dispose();
    });

    test('YouTube tab without subscriptions shows the subscribe call to action',
        () async {
      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([
          _youtubeSeries('c', 'Alpha Channel', 50),
        ]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: _FakeChannelService(const {}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.selectFormat(AudioFormat.youtube);

      expect(controller.state.filteredSeries, isEmpty);
      expect(controller.state.hasChannelSubscriptions, isFalse);
      expect(controller.state.shouldShowSubscribedCta, isTrue);

      controller.dispose();
    });

    test('archive format ignores channel subscriptions', () async {
      final archive = _series('a1', 'Romans Exposition');
      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([archive]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: _FakeChannelService(const {}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Default format is archive: no subscriptions yet, but archive content
      // must still be reachable and the CTA must not appear.
      expect(controller.state.filteredSeries.map((s) => s.id), ['a1']);
      expect(controller.state.shouldShowSubscribedCta, isFalse);

      controller.dispose();
    });

    test('subscription changes propagate from ChannelService into state',
        () async {
      final series = _youtubeSeries('c', 'Alpha Channel', 50);
      final channelService = _FakeChannelService(const {});
      final controller = AudioLibraryController(
        catalogService: _FakeCatalogService([series]),
        storageService: _FakeStorageService(),
        langController: LibraryLanguagesController(),
        channelService: channelService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.selectFormat(AudioFormat.youtube);
      expect(controller.state.shouldShowSubscribedCta, isTrue);

      // User subscribes elsewhere (e.g. ChannelsScreen): state reacts live.
      channelService.setSubscription({'Alpha Channel'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.state.filteredSeries.map((s) => s.id), ['c']);
      expect(controller.state.shouldShowSubscribedCta, isFalse);

      // Unsubscribing brings the call to action back.
      channelService.setSubscription(const {});
      expect(controller.state.filteredSeries, isEmpty);
      expect(controller.state.shouldShowSubscribedCta, isTrue);

      controller.dispose();
    });
  });
}
