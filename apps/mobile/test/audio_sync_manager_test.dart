import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/audio/adapters/sqlite_audio_catalog_adapter.dart';
import 'package:mobile/features/audio/services/audio_sync_manager.dart';
import 'package:mobile/features/audio/models/audio_series.dart';

class MockSqliteAdapter extends Mock implements SqliteAudioCatalogAdapter {}
class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('AudioSyncManager', () {
    late MockSqliteAdapter mockSqliteAdapter;
    late MockHttpClient mockHttpClient;
    late AudioSyncManager syncManager;

    setUp(() {
      mockSqliteAdapter = MockSqliteAdapter();
      mockHttpClient = MockHttpClient();
      syncManager = AudioSyncManager(mockSqliteAdapter, client: mockHttpClient);
      
      registerFallbackValue(Uri.parse('http://localhost'));
      registerFallbackValue(const AudioSeries(
        id: 'dummy',
        title: 'dummy',
        description: '',
        speaker: '',
        category: '',
        language: '',
        trackCount: 0,
        tracks: [],
      ));
      when(() => mockSqliteAdapter.upsertSeries(
            any(),
            updatedAtMs: any(named: 'updatedAtMs'),
          ))
          .thenAnswer((_) async {});
    });

    test('syncCatalog does nothing if no updates', () async {
      when(() => mockSqliteAdapter.getLastSyncTimestamp()).thenAnswer((_) async => 1000);
      when(() => mockHttpClient.get(any())).thenAnswer((_) async => http.Response('{"data": []}', 200));

      await syncManager.syncCatalog();

      verify(() => mockSqliteAdapter.getLastSyncTimestamp()).called(1);
      verify(() => mockHttpClient.get(any())).called(1);
      verifyNever(() => mockSqliteAdapter.upsertSeries(any(), updatedAtMs: any(named: 'updatedAtMs')));
    });

    test('syncCatalog persists the server updatedAt as the cursor, not client now', () async {
      when(() => mockSqliteAdapter.getLastSyncTimestamp()).thenAnswer((_) async => 0);
      const body = '''
      {
        "data": [
          {
            "id": "yt1",
            "title": "CFC India Sermons",
            "description": "",
            "speaker": "Zac Poonen",
            "category": "YouTube",
            "language": "en",
            "trackCount": 2,
            "updatedAt": "2026-09-11T08:30:00.000Z",
            "tracks": []
          }
        ]
      }
      ''';
      when(() => mockHttpClient.get(any()))
          .thenAnswer((_) async => http.Response(body, 200));

      await syncManager.syncCatalog();

      final storedCursor = verify(() => mockSqliteAdapter.upsertSeries(
        any(),
        updatedAtMs: captureAny(named: 'updatedAtMs'),
      )).captured.single as int;
      expect(storedCursor, DateTime.utc(2026, 9, 11, 8, 30).millisecondsSinceEpoch);
    });

    test('syncCatalog sends the incremental since cursor by default', () async {
      when(() => mockSqliteAdapter.getLastSyncTimestamp()).thenAnswer((_) async => 123456789);
      when(() => mockHttpClient.get(any()))
          .thenAnswer((_) async => http.Response('{"data": []}', 200));

      await syncManager.syncCatalog();

      final uri = verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;
      expect(uri.queryParameters['since'], '123456789');
    });

    test('syncCatalog(fullRefresh: true) omits the since cursor and does not read one', () async {
      when(() => mockHttpClient.get(any()))
          .thenAnswer((_) async => http.Response('{"data": []}', 200));

      await syncManager.syncCatalog(fullRefresh: true);

      final uri = verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;
      expect(uri.queryParameters.containsKey('since'), isFalse);
      verifyNever(() => mockSqliteAdapter.getLastSyncTimestamp());
    });
  });
}
