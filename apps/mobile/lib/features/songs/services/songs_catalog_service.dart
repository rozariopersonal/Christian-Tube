import 'package:http/http.dart' as http;

import '../adapters/remote_song_catalog_adapter.dart';
import '../adapters/song_catalog_adapter.dart';
import '../models/song.dart';

/// Thin facade over the [SongCatalogAdapter] so callers stay decoupled from
/// the concrete data source.
class SongsCatalogService {
  final SongCatalogAdapter _adapter;

  SongsCatalogService({SongCatalogAdapter? adapter})
      : _adapter = adapter ?? RemoteSongCatalogAdapter();

  SongsCatalogService.withClient(http.Client client)
      : _adapter = RemoteSongCatalogAdapter(client: client);

  Future<List<Song>> getSongs({bool forceRefresh = false}) =>
      _adapter.fetchSongs(forceRefresh: forceRefresh);

  Future<Song?> getSong(String id, {bool forceRefresh = false}) =>
      _adapter.fetchSong(id, forceRefresh: forceRefresh);
}
