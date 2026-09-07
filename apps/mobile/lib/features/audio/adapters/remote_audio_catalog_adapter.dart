import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api/github_data_service.dart';
import '../models/audio_series.dart';
import 'audio_catalog_adapter.dart';
import 'seed_audio_catalog.dart';

/// Fetches the dynamically updated CFC India audio catalog and series
/// tracklists from the releases repository (jsDelivr Edge CDN / GitHub), with
/// an offline seed fallback. Audio media itself streams directly from official
/// cfcindia.org servers.
class RemoteAudioCatalogAdapter implements AudioCatalogAdapter {
  final http.Client _client;
  static List<AudioSeries>? _cachedCatalog;
  static final Map<String, AudioSeries> _cachedSeries = {};

  RemoteAudioCatalogAdapter({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<List<AudioSeries>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      return _cachedCatalog!;
    }

    final urls = GitHubDataService.audioCatalogUrls();
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List<dynamic>;
          final parsed = list
              .map((e) => AudioSeries.fromJson(e as Map<String, dynamic>))
              .toList();
          _cachedCatalog = parsed;
          return parsed;
        }
      } catch (_) {
        // Try next fallback URL
      }
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

    final urls = GitHubDataService.audioSeriesUrls(seriesId);
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final series = AudioSeries.fromJson(map);
          _cachedSeries[seriesId] = series;
          return series;
        }
      } catch (_) {
        // Try next fallback URL
      }
    }

    // Return seed series if available
    final fallback = SeedAudioCatalog.seriesById[seriesId];
    if (fallback != null) {
      _cachedSeries[seriesId] = fallback;
    }
    return fallback;
  }
}