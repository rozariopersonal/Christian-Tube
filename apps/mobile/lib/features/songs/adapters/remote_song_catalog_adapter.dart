import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/api/github_data_service.dart';
import '../../../core/api/release_assets.dart';
import '../models/song.dart';
import 'song_catalog_adapter.dart';

/// Fetches the song catalog from the releases repository
/// (jsDelivr Edge CDN / GitHub), with disk caching by dataset revision
/// and on-demand streaming of full lyrics when lean catalog is used.
class RemoteSongCatalogAdapter implements SongCatalogAdapter {
  static List<Song>? _cachedSongs;
  static final Map<String, Song> _cachedById = {};
  final Dio _dio;
  final http.Client? _httpClient;

  RemoteSongCatalogAdapter({Dio? dio, http.Client? client})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _httpClient = client;

  @visibleForTesting
  static void clearMemoryCache() {
    _cachedSongs = null;
    _cachedById.clear();
  }

  Future<File?> _getCacheFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'songs_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final rev =
          ReleaseAssets.revision.trim().replaceAll(RegExp(r'[^\w]'), '_');
      final fileName =
          rev.isEmpty ? 'catalog_lite.json' : 'catalog_lite_$rev.json';
      return File(p.join(cacheDir.path, fileName));
    } catch (_) {
      return null;
    }
  }

  Future<File?> _getSongItemCacheFile(String id) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'songs_cache', 'items'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      return File(p.join(cacheDir.path, '$id.json'));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Song>> fetchSongs({bool forceRefresh = false}) async {
    if (_httpClient != null) {
      final urls = [
        ...GitHubDataService.songsCatalogLiteUrls(),
        ...GitHubDataService.songsCatalogUrls(),
      ];
      for (final url in urls) {
        try {
          final res = await _httpClient.get(Uri.parse(url)).timeout(
                const Duration(seconds: 4),
              );
          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body);
            final rawList = decoded is Map<String, dynamic>
                ? decoded['songs']
                : decoded;
            if (rawList is! List<dynamic>) continue;
            final parsed = rawList
                .map((e) => Song.fromJson(e as Map<String, dynamic>))
                .toList();
            return parsed;
          }
        } catch (_) {}
      }
      return const [];
    }

    if (!forceRefresh && _cachedSongs != null && _cachedSongs!.isNotEmpty) {
      return _cachedSongs!;
    }

    // 1. Try disk cache if not force refresh
    final cacheFile = await _getCacheFile();
    if (!forceRefresh && cacheFile != null && await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final decoded = jsonDecode(content);
        final rawList =
            decoded is Map<String, dynamic> ? decoded['songs'] : decoded;
        if (rawList is List<dynamic>) {
          final parsed = rawList
              .map((e) => Song.fromJson(e as Map<String, dynamic>))
              .toList();
          _cachedSongs = parsed;
          for (final s in parsed) {
            _cachedById.putIfAbsent(s.id, () => s);
          }
          return parsed;
        }
      } catch (e) {
        debugPrint('Failed to read songs disk cache: $e');
      }
    }

    // 2. Fetch lean catalog (CDN first, with fallback to full catalog)
    final urls = [
      ...GitHubDataService.songsCatalogLiteUrls(),
      ...GitHubDataService.songsCatalogUrls(),
    ];

    for (final url in urls) {
      try {
        final res = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        if (res.statusCode == 200 && res.data != null) {
          final decoded = jsonDecode(res.data!);
          final rawList = decoded is Map<String, dynamic>
              ? decoded['songs']
              : decoded;
          if (rawList is! List<dynamic>) continue;

          final parsed = rawList
              .map((e) => Song.fromJson(e as Map<String, dynamic>))
              .toList();
          _cachedSongs = parsed;
          for (final s in parsed) {
            _cachedById[s.id] = s;
          }

          // Persist to disk cache
          if (cacheFile != null) {
            try {
              await cacheFile.writeAsString(res.data!);
            } catch (_) {}
          }

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
    final existing = _cachedById[songId];
    if (!forceRefresh && existing != null && existing.verses.isNotEmpty) {
      return existing;
    }

    // Check disk item cache
    final itemFile = await _getSongItemCacheFile(songId);
    if (!forceRefresh && itemFile != null && await itemFile.exists()) {
      try {
        final content = await itemFile.readAsString();
        final song =
            Song.fromJson(jsonDecode(content) as Map<String, dynamic>);
        _cachedById[songId] = song;
        return song;
      } catch (_) {}
    }

    // Stream single song on-demand
    final urls = GitHubDataService.songItemUrls(songId);
    for (final url in urls) {
      try {
        final res = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        if (res.statusCode == 200 && res.data != null) {
          final song =
              Song.fromJson(jsonDecode(res.data!) as Map<String, dynamic>);
          _cachedById[songId] = song;
          if (itemFile != null) {
            try {
              await itemFile.writeAsString(res.data!);
            } catch (_) {}
          }
          return song;
        }
      } catch (_) {}
    }

    // Fall back to catalog entry if available
    return existing;
  }

  @override
  Future<List<Song>> search(String query, {int limit = 50}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final songs = await fetchSongs();
    return songs.where((s) => s.matchesQuery(term)).take(limit).toList();
  }
}

