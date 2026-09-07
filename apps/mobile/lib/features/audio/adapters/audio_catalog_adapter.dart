import '../models/audio_series.dart';

/// Contract for audio catalog data sources (remote releases repository, seed
/// fallback, future offline mirrors). Follows the books feature's adapter
/// pattern so the catalog service stays a thin facade.
abstract class AudioCatalogAdapter {
  Future<List<AudioSeries>> fetchCatalog({bool forceRefresh = false});

  Future<AudioSeries?> fetchSeries(String seriesId, {bool forceRefresh = false});
}