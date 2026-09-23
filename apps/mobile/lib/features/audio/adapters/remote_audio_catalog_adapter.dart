import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../models/audio_series.dart';
import 'audio_catalog_adapter.dart';
import 'seed_audio_catalog.dart';

/// Fetches the audio catalog and series tracklists from the backend database
/// (DB-first) via `GET /api/audio/catalog` and `GET /api/audio/series/{id}`,
/// with an offline seed fallback. Audio media itself streams directly from
/// official cfcindia.org / Audio.com servers.
class RemoteAudioCatalogAdapter implements AudioCatalogAdapter {
  final http.Client _client;
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

  RemoteAudioCatalogAdapter({http.Client? client})
      : _client = client ?? http.Client();

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
      // Fall through to seed catalog below.
    }

    // Fallback seed catalog if offline
    _cachedCatalog = SeedAudioCatalog.catalog;
    return SeedAudioCatalog.catalog;
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
      // Fall through to seed series fallback below.
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
      final url = Uri.parse('${AppConfig.apiBaseUrl}/api/audio/search?q=$query&limit=20');
      final res = await _client.get(url).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['data'] as List<dynamic>? ?? [];
        return list.map((e) => AudioSeries.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // Ignore network errors for search
    }
    return [];
  }
}
