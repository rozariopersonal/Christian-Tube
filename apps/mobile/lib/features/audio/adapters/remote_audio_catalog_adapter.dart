import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../models/audio_series.dart';
import 'audio_catalog_adapter.dart';
import 'seed_audio_catalog.dart';

/// Fetches the audio catalog and series tracklists from the backend database
/// (DB-first) via `GET /api/audio/catalog` and `GET /api/audio/series/{id}`,
/// with an offline fallback. Audio media itself streams directly from
/// official cfcindia.org / Audio.com servers.
///
/// When the backend is unreachable, an optional `offlineFallback` (the SQLite
/// mirror) is consulted before the embedded seed catalog, so airplane users see
/// the full synced catalog rather than a handful of seed entries.
class RemoteAudioCatalogAdapter implements AudioCatalogAdapter {
  final http.Client _client;
  final AudioCatalogAdapter? _offlineFallback;
  static List<AudioSeries>? _cachedCatalog;
  static final Map<String, AudioSeries> _cachedSeries = {};

  /// Clears the in-memory catalog and series caches so the next fetch honors a
  /// fresh network pull (used on force-refresh after a new dataset revision).
  static void invalidateCache() {
    _cachedCatalog = null;
    _cachedSeries.clear();
  }

  @visibleForTesting
  static void seedCacheForTesting([List<AudioSeries>? catalog]) {
    _cachedCatalog = catalog ?? SeedAudioCatalog.catalog;
  }

  RemoteAudioCatalogAdapter({http.Client? client, AudioCatalogAdapter? offlineFallback})
      : _client = client ?? http.Client(),
        _offlineFallback = offlineFallback;

  @override
  Future<bool> get isReady async => true;

  @override
  Future<List<AudioSeries>> fetchCatalog({bool forceRefresh = false}) async {
    if (forceRefresh) {
      RemoteAudioCatalogAdapter.invalidateCache();
    }
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      return _cachedCatalog!;
    }

    final url = Uri.parse('${AppConfig.apiBaseUrl}/api/audio/catalog');
    try {
      final res = await _client.get(url).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>? ?? [])
            .map((e) => AudioSeries.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          _cachedCatalog = list;
          return list;
        }
      }
    } catch (_) {
      // Fall through to offline fallback below.
    }

    // Offline: prefer the synced local mirror over the tiny embedded seed.
    final offline = await _tryOfflineCatalog();
    if (offline != null) {
      _cachedCatalog = offline;
      return offline;
    }

    // Fallback seed catalog if offline
    _cachedCatalog = SeedAudioCatalog.catalog;
    return SeedAudioCatalog.catalog;
  }

  Future<List<AudioSeries>?> _tryOfflineCatalog() async {
    final fallback = _offlineFallback;
    if (fallback == null || !await _isOfflineReady(fallback)) return null;
    try {
      final local = await fallback.fetchCatalog();
      if (local.isNotEmpty) return local;
    } catch (_) {
      // Offline mirror unavailable (e.g. never synced); caller decides.
    }
    return null;
  }

  Future<bool> _isOfflineReady(AudioCatalogAdapter fallback) async {
    try {
      final ready = await fallback.isReady;
      if (ready) return true;
    } catch (_) {
      // Mirror cannot report readiness (plugin missing / DB absent).
    }
    return false;
  }

  @override
  Future<AudioSeries?> fetchSeries(
    String seriesId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedSeries.containsKey(seriesId)) {
      return _cachedSeries[seriesId];
    }

    final url = Uri.parse('${AppConfig.apiBaseUrl}/api/audio/series/$seriesId');
    try {
      final res = await _client.get(url).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final map = body['data'] as Map<String, dynamic>?;
        if (map != null) {
          final series = AudioSeries.fromJson(map);
          _cachedSeries[seriesId] = series;
          return series;
        }
      }
    } catch (_) {
      // Fall through to offline fallback below.
    }

    // Offline: prefer the synced local mirror over the embedded seed series.
    final offlineFallback = _offlineFallback;
    if (offlineFallback != null && await _isOfflineReady(offlineFallback)) {
      try {
        final local = await offlineFallback.fetchSeries(seriesId);
        if (local != null) {
          _cachedSeries[seriesId] = local;
          return local;
        }
      } catch (_) {
        // Offline mirror unavailable; fall through to the seed.
      }
    }

    // Return seed series if available
    final fallback = SeedAudioCatalog.seriesById[seriesId];
    if (fallback != null) {
      _cachedSeries[seriesId] = fallback;
    }
    return fallback;
  }

  @override
  Future<List<AudioSeries>> search(String query) async {
    try {
      final url = Uri.parse('${AppConfig.apiBaseUrl}/api/audio/search')
          .replace(queryParameters: {'q': query, 'limit': '20'});
      final res = await _client.get(url).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['data'] as List<dynamic>? ?? [];
        return list.map((e) => AudioSeries.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // Ignore network errors for search; try the offline mirror below.
    }

    final offlineFallback = _offlineFallback;
    if (offlineFallback != null && await _isOfflineReady(offlineFallback)) {
      try {
        return await offlineFallback.search(query);
      } catch (_) {
        // Offline mirror unavailable; return empty.
      }
    }
    return [];
  }
}
