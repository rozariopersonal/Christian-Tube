import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/features/audio/adapters/remote_audio_catalog_adapter.dart';
import 'package:mobile/features/audio/adapters/seed_audio_catalog.dart';

void main() {
  setUp(() {
    RemoteAudioCatalogAdapter.invalidateCache();
  });

  group('RemoteAudioCatalogAdapter.fetchCatalog (DB-first)', () {
    test('reads the catalog from GET /api/audio/catalog and parses data[]', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'sermon_one',
                'title': 'Sermon One',
                'description': 'First',
                'speaker': 'Zac Poonen',
                'coverUrl': 'http://cdn/cover.jpg',
                'trackCount': 4,
                'category': 'General',
                'language': 'English',
              },
            ],
          }),
          200,
        );
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      final catalog = await adapter.fetchCatalog();

      expect(requested, ['/api/audio/catalog']);
      expect(catalog, hasLength(1));
      expect(catalog.first.id, 'sermon_one');
      expect(catalog.first.trackCount, 4);
      expect(catalog.first.tracks, isEmpty);
    });

    test('does not hit the releases CDN any more', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response(jsonEncode({'data': []}), 200);
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      await adapter.fetchCatalog();

      expect(hosts, isNot(contains('cdn.jsdelivr.net')));
      expect(hosts, isNot(contains('raw.githubusercontent.com')));
    });

    test('caches the catalog so a second fetch makes no network call', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 's1', 'title': 'S1', 'trackCount': 1},
            ],
          }),
          200,
        );
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      await adapter.fetchCatalog();
      await adapter.fetchCatalog();
      expect(calls, 1);

      await adapter.fetchCatalog(forceRefresh: true);
      expect(calls, 2);
    });

    test('falls back to the seed catalog when the API errors', () async {
      final client = MockClient((request) async => http.Response('boom', 500));
      final adapter = RemoteAudioCatalogAdapter(client: client);

      final catalog = await adapter.fetchCatalog();

      expect(catalog, same(SeedAudioCatalog.catalog));
      expect(catalog.any((s) => s.id == 'through_the_bible'), isTrue);
    });

    test('falls back to the seed catalog when the body is not valid JSON', () async {
      final client = MockClient(
        (request) async => http.Response('<html>gateway timeout</html>', 200),
      );
      final adapter = RemoteAudioCatalogAdapter(client: client);

      final catalog = await adapter.fetchCatalog();

      expect(catalog, same(SeedAudioCatalog.catalog));
    });

    test('falls back to the seed catalog when data[] is empty', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'data': []}), 200),
      );
      final adapter = RemoteAudioCatalogAdapter(client: client);

      final catalog = await adapter.fetchCatalog();

      expect(catalog, same(SeedAudioCatalog.catalog));
    });
  });

  group('RemoteAudioCatalogAdapter.fetchSeries (DB-first)', () {
    test('reads the series from GET /api/audio/series/{id} with tracks', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': {
              'id': 'sermon_one',
              'title': 'Sermon One',
              'description': 'First',
              'speaker': 'Zac Poonen',
              'coverUrl': 'http://cdn/cover.jpg',
              'trackCount': 1,
              'category': 'General',
              'language': 'English',
              'tracks': [
                {
                  'id': 't1',
                  'seriesId': 'sermon_one',
                  'seriesTitle': 'Sermon One',
                  'title': 'Track 1',
                  'speaker': 'Zac Poonen',
                  'durationSeconds': 120,
                  'audioUrl': 'https://audio.com/98765',
                  'coverUrl': 'http://cdn/track.jpg',
                },
              ],
            },
          }),
          200,
        );
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      final series = await adapter.fetchSeries('sermon_one');

      expect(requested, ['/api/audio/series/sermon_one']);
      expect(series, isNotNull);
      expect(series!.tracks, hasLength(1));
      expect(series.tracks.first.seriesTitle, 'Sermon One');
      expect(series.tracks.first.coverUrl, 'http://cdn/track.jpg');
      // audio.com tracks resolve to the backend stream endpoint.
      expect(
        series.tracks.first.streamUrl,
        '${AppConfig.apiBaseUrl}/audio/stream/98765',
      );
    });

    test('caches the series so a second fetch makes no network call', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': {'id': 's1', 'title': 'S1', 'trackCount': 0},
          }),
          200,
        );
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      await adapter.fetchSeries('s1');
      await adapter.fetchSeries('s1');
      expect(calls, 1);
    });

    test('falls back to the seed series when the API errors', () async {
      final client = MockClient((request) async => http.Response('boom', 503));
      final adapter = RemoteAudioCatalogAdapter(client: client);

      final series = await adapter.fetchSeries('through_the_bible');

      expect(series, isNotNull);
      expect(series!.id, 'through_the_bible');
      expect(series.tracks, isNotEmpty);
    });

    test('returns null when the API errors and no seed series exists', () async {
      final client = MockClient((request) async => http.Response('boom', 404));
      final adapter = RemoteAudioCatalogAdapter(client: client);

      final series = await adapter.fetchSeries('definitely_not_in_seed');
      expect(series, isNull);
    });

    test('returns null when the API reports the series as missing (404)', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'message': 'nope'}), 404),
      );
      final adapter = RemoteAudioCatalogAdapter(client: client);

      final series = await adapter.fetchSeries('unknown_series');
      expect(series, isNull);
    });
  });

  group('RemoteAudioCatalogAdapter.search', () {
    test('reads search results from GET /api/audio/search', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 's1', 'title': 'Faith Series', 'trackCount': 0},
            ],
          }),
          200,
        );
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      final results = await adapter.search('faith');

      expect(requested, ['/api/audio/search']);
      expect(results, hasLength(1));
      expect(results.first.title, 'Faith Series');
    });

    test('URL-encodes the query (spaces & special chars survive)', () async {
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode({'data': []}), 200);
      });

      final adapter = RemoteAudioCatalogAdapter(client: client);
      await adapter.search('Ministry of a Deliverer & more');

      expect(captured.path, '/api/audio/search');
      expect(captured.queryParameters['q'], 'Ministry of a Deliverer & more');
      expect(captured.queryParameters['limit'], '20');
    });

    test('returns an empty list when search fails', () async {
      final client = MockClient((request) async => http.Response('nope', 500));
      final adapter = RemoteAudioCatalogAdapter(client: client);
      expect(await adapter.search('anything'), isEmpty);
    });
  });
}
