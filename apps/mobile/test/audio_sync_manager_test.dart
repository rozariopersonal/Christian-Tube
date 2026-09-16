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
    });

    test('syncCatalog does nothing if no updates', () async {
      when(() => mockSqliteAdapter.getLastSyncTimestamp()).thenAnswer((_) async => 1000);
      when(() => mockHttpClient.get(any())).thenAnswer((_) async => http.Response('{"data": []}', 200));

      await syncManager.syncCatalog();

      verify(() => mockSqliteAdapter.getLastSyncTimestamp()).called(1);
      verify(() => mockHttpClient.get(any())).called(1);
      verifyNever(() => mockSqliteAdapter.upsertSeries(any(), updatedAtMs: any(named: 'updatedAtMs')));
    });
  });
}
