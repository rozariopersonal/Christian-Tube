import '../models/song.dart';

/// Contract for any songs catalog data source.
///
/// Implementations (GitHub releases, backend API, local SQLite, etc.) can
/// provide songs in any language/corpus; the controllers and screens never
/// depend on a specific source.
abstract class SongCatalogAdapter {
  /// Fetches the full list of songs.
  Future<List<Song>> fetchSongs({bool forceRefresh = false});

  /// Fetches a single song by id, or null if unknown.
  Future<Song?> fetchSong(String songId, {bool forceRefresh = false});
}
