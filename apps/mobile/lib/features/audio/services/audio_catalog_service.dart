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
  static bool _isCacheLoaded = false;

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
    _isCacheLoaded = false;
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