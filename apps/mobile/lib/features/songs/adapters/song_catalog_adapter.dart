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

  /// Rich search across titles, authors, collections, and lyrics.
  ///
  /// Implementations may use the local SQLite FTS5 index (when installed) or
  /// fall back to an in-memory filter. Results are ordered by relevance and
  /// capped at [limit].
  Future<List<Song>> search(String query, {int limit = 50});
}
