import 'package:http/http.dart' as http;

import '../adapters/remote_audio_catalog_adapter.dart';
import '../adapters/sqlite_audio_catalog_adapter.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';

/// DB-first router for the audio catalog.
/// The catalog is always read from the backend PostgreSQL database via the
/// remote adapter. The local SQLite mirror is only an OFFLINE cache: the
/// remote adapter consults it when the DB is unreachable, so it is never the
/// primary read source and can't serve stale data while the backend is up.
class AudioCatalogService {
  final SqliteAudioCatalogAdapter _localAdapter;
  final RemoteAudioCatalogAdapter _remoteAdapter;
  
  static final Map<String, AudioTrack> _youtubeIdCache = {};

  AudioCatalogService({
    http.Client? client,
    SqliteAudioCatalogAdapter? localAdapter,
    RemoteAudioCatalogAdapter? remoteAdapter,
  })  : _localAdapter = localAdapter ?? SqliteAudioCatalogAdapter(),
        _remoteAdapter = remoteAdapter ??
            RemoteAudioCatalogAdapter(
              client: client,
              offlineFallback: localAdapter ?? SqliteAudioCatalogAdapter(),
            );

  SqliteAudioCatalogAdapter get localAdapter => _localAdapter;
  RemoteAudioCatalogAdapter get remoteAdapter => _remoteAdapter;

  /// Clears in-memory caches (remote catalog/series + YouTube-id lookups) so
  /// the next read performs a fresh fetch. Used on force-refresh.
  void invalidateCaches() {
    RemoteAudioCatalogAdapter.invalidateCache();
    _youtubeIdCache.clear();
  }

  /// Look up an audio track by its associated YouTube Video ID.
  /// Directly queries the backend endpoint with offline fallback to the local SQLite mirror.
  Future<AudioTrack?> findTrackByYoutubeId(String videoId) async {
    if (videoId.isEmpty) return null;
    if (_youtubeIdCache.containsKey(videoId)) {
      return _youtubeIdCache[videoId];
    }

    try {
      final remoteTrack = await _remoteAdapter.fetchTrackByYoutubeId(videoId);
      if (remoteTrack != null) {
        _youtubeIdCache[videoId] = remoteTrack;
        return remoteTrack;
      }
    } catch (_) {}

    try {
      final localTrack = await _localAdapter.findTrackByYoutubeId(videoId);
      if (localTrack != null) {
        _youtubeIdCache[videoId] = localTrack;
        return localTrack;
      }
    } catch (_) {}

    return null;
  }

  /// Loads the top-level audio catalog from the backend database.
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) async {
    return _remoteAdapter.fetchCatalog(forceRefresh: forceRefresh);
  }

  /// Loads the full series with tracks from the backend database.
  Future<AudioSeries?> getSeries(
    String seriesId, {
    bool forceRefresh = false,
  }) async {
    return _remoteAdapter.fetchSeries(seriesId, forceRefresh: forceRefresh);
  }
  
  /// Searches the audio catalog via the backend search API (with an offline
  /// fallback to the local SQLite FTS mirror).
  Future<List<AudioSeries>> search(String query) async {
    if (query.trim().isEmpty) return [];
    return _remoteAdapter.search(query);
  }
}