import 'package:http/http.dart' as http;

import '../adapters/audio_catalog_adapter.dart';
import '../adapters/remote_audio_catalog_adapter.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';

/// Thin facade over the audio catalog [AudioCatalogAdapter] layer (mirrors the
/// books feature's `BookService` pattern). The adapter reads from the releases
/// repository with an offline seed fallback.
class AudioCatalogService {
  final AudioCatalogAdapter _adapter;
  
  static final Map<String, AudioTrack> _youtubeIdCache = {};
  static bool _isCacheLoaded = false;

  AudioCatalogService({http.Client? client})
      : _adapter = RemoteAudioCatalogAdapter(client: client);

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

  /// Loads the top-level audio catalog dynamically from the releases repository.
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) =>
      _adapter.fetchCatalog(forceRefresh: forceRefresh);

  /// Loads the full series with tracks dynamically from the releases repository.
  Future<AudioSeries?> getSeries(
    String seriesId, {
    bool forceRefresh = false,
  }) =>
      _adapter.fetchSeries(seriesId, forceRefresh: forceRefresh);
}