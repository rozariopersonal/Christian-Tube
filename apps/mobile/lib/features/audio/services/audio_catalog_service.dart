import 'package:http/http.dart' as http;

import '../adapters/audio_catalog_adapter.dart';
import '../adapters/remote_audio_catalog_adapter.dart';
import '../models/audio_series.dart';

/// Thin facade over the audio catalog [AudioCatalogAdapter] layer (mirrors the
/// books feature's `BookService` pattern). The adapter reads from the releases
/// repository with an offline seed fallback.
class AudioCatalogService {
  final AudioCatalogAdapter _adapter;

  AudioCatalogService({http.Client? client})
      : _adapter = RemoteAudioCatalogAdapter(client: client);

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