import '../models/audio_series.dart';

/// Contract for audio catalog data sources (remote releases repository, seed
/// fallback, future offline mirrors). Follows the books feature's adapter
/// pattern so the catalog service stays a thin facade.
abstract class AudioCatalogAdapter {
  Future<List<AudioSeries>> fetchCatalog({bool forceRefresh = false});

  Future<AudioSeries?> fetchSeries(String seriesId, {bool forceRefresh = false});
  
  Future<List<AudioSeries>> search(String query);

  /// Whether this adapter holds real, usable data. Remote is always ready;
  /// a SQLite mirror is ready only after it has been synced. Offline fallbacks
  /// check this before reading so an empty mirror is never created or served.
  Future<bool> get isReady async => true;
}