import 'package:http/http.dart' as http;

import '../adapters/audio_catalog_adapter.dart';
import '../adapters/remote_audio_catalog_adapter.dart';
import '../adapters/sqlite_audio_catalog_adapter.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';

/// Hybrid router for audio catalog. 
/// If the SQLite database is initialized (i.e. sync has run), it serves data and search locally.
/// Otherwise, it falls back to the remote adapter (GitHub fetching + NestJS search API).
class AudioCatalogService {
  final SqliteAudioCatalogAdapter _localAdapter;
  final RemoteAudioCatalogAdapter _remoteAdapter;
  
  static final Map<String, AudioTrack> _youtubeIdCache = {};
  static bool _isCacheLoaded = false;

  AudioCatalogService({http.Client? client})
      : _localAdapter = SqliteAudioCatalogAdapter(),
        _remoteAdapter = RemoteAudioCatalogAdapter(client: client);

  Future<AudioCatalogAdapter> _getAdapter() async {
    if (await _localAdapter.isInitialized) {
      return _localAdapter;
    }
    return _remoteAdapter;
  }

  /// Look up an audio track by its associated YouTube Video ID.
  /// Caches the Audio.com uploads series in memory for instant subsequent lookups.
  Future<AudioTrack?> findTrackByYoutubeId(String videoId) async {
    if (!_isCacheLoaded) {
      try {
        final catalog = await getCatalog();
        final seriesFutures = catalog.map((s) => getSeries(s.id));
        final allSeries = await Future.wait(seriesFutures);

        for (final series in allSeries) {
          if (series != null) {
            for (final track in series.tracks) {
              if (track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty) {
                _youtubeIdCache[track.youtubeVideoId!] = track;
              }
            }
          }
        }
        _isCacheLoaded = true;
      } catch (_) {
        // Ignore errors; cache stays empty or partial
      }
    }
    return _youtubeIdCache[videoId];
  }

  /// Loads the top-level audio catalog dynamically from local SQLite or remote.
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) async {
    final adapter = await _getAdapter();
    return adapter.fetchCatalog(forceRefresh: forceRefresh);
  }

  /// Loads the full series with tracks dynamically from local SQLite or remote.
  Future<AudioSeries?> getSeries(
    String seriesId, {
    bool forceRefresh = false,
  }) async {
    final adapter = await _getAdapter();
    return adapter.fetchSeries(seriesId, forceRefresh: forceRefresh);
  }
  
  /// Searches the audio catalog locally via FTS5 or remotely via API.
  Future<List<AudioSeries>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final adapter = await _getAdapter();
    return adapter.search(query);
  }
}