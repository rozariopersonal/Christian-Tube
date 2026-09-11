import 'package:http/http.dart' as http;

import '../models/song.dart';
import 'remote_song_catalog_adapter.dart';
import 'song_catalog_adapter.dart';
import 'sqlite_songs_catalog_adapter.dart';

/// Default on-device songs source: prefers the locally installed SQLite
/// package (offline browsing + FTS5 search) and falls back to the live JSON
/// catalog while nothing is installed.
///
/// Mirrors the dictionary pattern where a static catalog list is replaced by
/// the full package only after the optional download completes.
class OfflineSongsCatalogAdapter implements SongCatalogAdapter {
  final SqliteSongsCatalogAdapter _sqlite;
  final RemoteSongCatalogAdapter _remote;

  OfflineSongsCatalogAdapter({http.Client? client, String? dbPathOverride})
      : _sqlite = SqliteSongsCatalogAdapter(dbPathOverride: dbPathOverride),
        _remote = RemoteSongCatalogAdapter(client: client);

  Future<bool> get _localAvailable => _sqlite.isInstalled;

  @override
  Future<List<Song>> fetchSongs({bool forceRefresh = false}) async {
    if (await _localAvailable) return _sqlite.fetchSongs();
    return _remote.fetchSongs(forceRefresh: forceRefresh);
  }

  @override
  Future<Song?> fetchSong(String songId, {bool forceRefresh = false}) async {
    if (await _localAvailable) {
      final local = await _sqlite.fetchSong(songId, forceRefresh: forceRefresh);
      if (local != null) return local;
    }
    return _remote.fetchSong(songId, forceRefresh: forceRefresh);
  }

  @override
  Future<List<Song>> search(String query, {int limit = 50}) async {
    if (await _localAvailable) {
      return _sqlite.search(query, limit: limit);
    }
    return _remote.search(query, limit: limit);
  }

  /// Releases the underlying database handle so the file can be replaced or
  /// deleted. Safe to call when nothing was ever opened.
  Future<void> close() => _sqlite.close();
}