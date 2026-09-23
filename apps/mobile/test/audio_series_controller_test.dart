import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/controllers/audio_series_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/services/audio_catalog_service.dart';
import 'package:mobile/features/audio/services/audio_storage_service.dart';

class _FakeCatalogService extends AudioCatalogService {
  final AudioSeries? series;
  _FakeCatalogService(this.series);

  @override
  Future<AudioSeries?> getSeries(String seriesId,
          {bool forceRefresh = false}) async =>
      series;
}

class _FakeStorageService extends AudioStorageService {
  @override
  Future<AudioTrack?> getLastTrack() async => null;

  @override
  Future<int> getPosition(String trackId) async => 0;
}

AudioTrack _track(String id, String title, {String speaker = 'Zac Poonen'}) {
  return AudioTrack(
    id: id,
    title: title,
    seriesId: 's1',
    seriesTitle: 'Test Series',
    speaker: speaker,
    durationSeconds: 300,
    audioUrl: 'https://example.com/$id.mp3',
  );
}

AudioSeries _series(List<AudioTrack> tracks) {
  return AudioSeries(
    id: 's1',
    title: 'Test Series',
    description: '',
    speaker: 'Zac Poonen',
    coverUrl: null,
    trackCount: tracks.length,
    category: 'Verse By Verse',
    language: 'en',
    tracks: tracks,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioSeriesViewState in-channel search', () {
    final tracks = [
      _track('1', 'Romans Exposition – Justification by Faith'),
      _track('2', 'Romans 5 – Peace with God'),
      _track('3', 'Kingdom of God Revealed', speaker: 'Ian Thomas'),
    ];

    test('filteredTracks returns everything when the query is blank', () {
      const state = AudioSeriesViewState(series: null);
      expect(state.isSearching, isFalse);
      expect(state.filteredTracks, isEmpty);

      final withSeries = state.copyWith(series: _series(tracks));
      expect(withSeries.filteredTracks.length, 3);
    });

    test('filteredTracks filters by title', () {
      final state = AudioSeriesViewState(series: _series(tracks))
          .copyWith(searchQuery: 'Romans');
      expect(state.isSearching, isTrue);
      expect(state.filteredTracks.length, 2);
      expect(state.filteredTracks.every((t) => t.title.contains('Romans')),
          isTrue);
    });

    test('filteredTracks filters by speaker', () {
      final state = AudioSeriesViewState(series: _series(tracks))
          .copyWith(searchQuery: 'Ian Thomas');
      expect(state.filteredTracks.length, 1);
      expect(state.filteredTracks.first.title, 'Kingdom of God Revealed');
    });

    test('filteredTracks is empty for a query that matches nothing', () {
      final state = AudioSeriesViewState(series: _series(tracks))
          .copyWith(searchQuery: 'zzz-no-match');
      expect(state.filteredTracks, isEmpty);
    });

    test('setSearchQuery updates state and clearSearch resets it', () {
      final controller = AudioSeriesController(
        seriesId: 's1',
        initialSeries: _series(tracks),
        catalogService: _FakeCatalogService(_series(tracks)),
        storageService: _FakeStorageService(),
      );

      controller.setSearchQuery('Romans');
      expect(controller.state.isSearching, isTrue);
      expect(controller.state.filteredTracks.length, 2);

      controller.clearSearch();
      expect(controller.state.isSearching, isFalse);
      expect(controller.state.filteredTracks.length, 3);

      controller.dispose();
    });
  });
}