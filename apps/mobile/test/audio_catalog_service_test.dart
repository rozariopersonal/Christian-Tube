import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/audio/adapters/remote_audio_catalog_adapter.dart';
import 'package:mobile/features/audio/adapters/sqlite_audio_catalog_adapter.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/services/audio_catalog_service.dart';

class _FakeLocalAdapter extends Mock implements SqliteAudioCatalogAdapter {}
class _FakeRemoteAdapter extends Mock implements RemoteAudioCatalogAdapter {}

AudioSeries _series(String id) => AudioSeries(
      id: id,
      title: id,
      description: '',
      speaker: '',
      category: '',
      language: '',
      trackCount: 0,
      tracks: const <AudioTrack>[],
    );

void main() {
  late _FakeLocalAdapter local;
  late _FakeRemoteAdapter remote;
  late AudioCatalogService service;

  setUp(() {
    local = _FakeLocalAdapter();
    remote = _FakeRemoteAdapter();
    service = AudioCatalogService(localAdapter: local, remoteAdapter: remote);
    registerFallbackValue(true);
  });

  group('AudioCatalogService DB-first routing', () {
    test('reads the catalog from the backend even when the mirror is initialized', () async {
      // Even a fully-synced SQLite mirror must never be the read source.
      when(() => local.isInitialized).thenAnswer((_) async => true);
      when(() => local.fetchCatalog(forceRefresh: any(named: 'forceRefresh')))
          .thenThrow(StateError('mirror must not be read while DB is up'));
      when(() => remote.fetchCatalog(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => [_series('db_series')]);

      final catalog = await service.getCatalog();

      expect(catalog.single.id, 'db_series');
      verify(() => remote.fetchCatalog(forceRefresh: any(named: 'forceRefresh'))).called(1);
    });

    test('reads series from the backend even when the mirror is initialized', () async {
      when(() => local.isInitialized).thenAnswer((_) async => true);
      when(() => local.fetchSeries(any(), forceRefresh: any(named: 'forceRefresh')))
          .thenThrow(StateError('mirror must not be read while DB is up'));
      when(() => remote.fetchSeries(any(), forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => _series('db_series'));

      final series = await service.getSeries('db_series');

      expect(series!.id, 'db_series');
      verify(() => remote.fetchSeries('db_series', forceRefresh: any(named: 'forceRefresh'))).called(1);
    });

    test('search goes through the backend, not the local FTS mirror', () async {
      when(() => local.isInitialized).thenAnswer((_) async => true);
      when(() => remote.search(any())).thenAnswer((_) async => [_series('hit')]);

      final results = await service.search('zac');

      expect(results.single.id, 'hit');
      verify(() => remote.search('zac')).called(1);
    });
  });
}