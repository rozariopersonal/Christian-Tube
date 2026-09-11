import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../adapters/offline_songs_catalog_adapter.dart';
import '../adapters/remote_song_catalog_adapter.dart';
import '../adapters/song_catalog_adapter.dart';
import '../models/song.dart';

/// Thin facade over the [SongCatalogAdapter] so callers stay decoupled from
/// the concrete data source.
///
/// On native platforms the default adapter prefers the locally installed
/// SQLite package and falls back to the live JSON catalog; on web the live
/// JSON catalog is always used (sqflite is unavailable there).
class SongsCatalogService {
  final SongCatalogAdapter _adapter;

  SongsCatalogService({SongCatalogAdapter? adapter})
      : _adapter = adapter ?? _defaultAdapter();

  SongsCatalogService.withClient(http.Client client)
      : _adapter = _defaultAdapter(client: client);

  static SongCatalogAdapter _defaultAdapter({http.Client? client}) {
    if (kIsWeb) return RemoteSongCatalogAdapter(client: client);
    return OfflineSongsCatalogAdapter(client: client);
  }

  Future<List<Song>> getSongs({bool forceRefresh = false}) =>
      _adapter.fetchSongs(forceRefresh: forceRefresh);

  Future<Song?> getSong(String id, {bool forceRefresh = false}) =>
      _adapter.fetchSong(id, forceRefresh: forceRefresh);

  /// Rich search across titles, authors, lyrics, and transliterations.
  Future<List<Song>> search(String query, {int limit = 50}) =>
      _adapter.search(query, limit: limit);
}