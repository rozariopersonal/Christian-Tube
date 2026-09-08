import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/api/github_data_service.dart';
import '../models/song.dart';
import 'song_catalog_adapter.dart';

/// Fetches the song catalog from the releases repository
/// (jsDelivr Edge CDN / GitHub), with an in-memory cache for the session.
///
/// The catalog is a single JSON file whose top-level shape is either
/// `{"songs": [...]}` or a bare `[...]` array; both are accepted.
class RemoteSongCatalogAdapter implements SongCatalogAdapter {
  final http.Client _client;
  static List<Song>? _cachedSongs;
  static final Map<String, Song> _cachedById = {};

  RemoteSongCatalogAdapter({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<List<Song>> fetchSongs({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSongs != null && _cachedSongs!.isNotEmpty) {
      return _cachedSongs!;
    }

    final urls = GitHubDataService.songsCatalogUrls();
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final rawList = decoded is Map<String, dynamic>
              ? decoded['songs']
              : decoded;
          if (rawList is! List<dynamic>) {
            debugPrint('Songs catalog at $url has an unexpected shape '
                '(expected {"songs":[...]} or [...])');
            continue;
          }
          final parsed = rawList
              .map((e) => Song.fromJson(e as Map<String, dynamic>))
              .toList();
          _cachedSongs = parsed;
          _cachedById
            ..clear()
            ..addEntries(parsed.map((s) => MapEntry(s.id, s)));
          return parsed;
        }
      } catch (_) {
        // Try next fallback URL
      }
    }

    return _cachedSongs ?? const [];
  }

  @override
  Future<Song?> fetchSong(
    String songId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedById.containsKey(songId)) {
      return _cachedById[songId];
    }
    await fetchSongs(forceRefresh: forceRefresh);
    return _cachedById[songId];
  }
}
