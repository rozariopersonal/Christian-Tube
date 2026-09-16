import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../adapters/sqlite_audio_catalog_adapter.dart';

class AudioSyncManager {
  final SqliteAudioCatalogAdapter _sqliteAdapter;
  final http.Client _client;

  AudioSyncManager(this._sqliteAdapter, {http.Client? client})
      : _client = client ?? http.Client();

  Future<void> syncCatalog() async {
    if (kIsWeb) return; // Web doesn't use local SQLite sync
    
    try {
      final lastSyncMs = await _sqliteAdapter.getLastSyncTimestamp();
      
      final url = Uri.parse('${AppConfig.apiBaseUrl}/api/audio/sync?since=$lastSyncMs');
      final response = await _client.get(url);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to sync audio catalog: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      final List<dynamic> seriesList = data['data'] ?? [];
      
      if (seriesList.isEmpty) {
        debugPrint('AudioSyncManager: No new updates found.');
        return;
      }
      
      debugPrint('AudioSyncManager: Syncing ${seriesList.length} updated series.');
      final currentMs = DateTime.now().millisecondsSinceEpoch;
      
      for (final s in seriesList) {
        final seriesId = s['id'] as String? ?? '';
        final seriesTitle = s['title'] as String? ?? '';
        final seriesSpeaker = s['speaker'] as String? ?? 'Zac Poonen';

        final series = AudioSeries(
          id: seriesId,
          title: seriesTitle,
          description: s['description'] ?? '',
          speaker: seriesSpeaker,
          category: s['category'] ?? '',
          language: s['language'] ?? '',
          coverUrl: s['coverUrl'],
          trackCount: s['trackCount'] ?? 0,
          tracks: (s['tracks'] as List<dynamic>? ?? []).map((trackJson) {
            return AudioTrack(
              id: trackJson['id'] as String,
              title: trackJson['title'] as String,
              seriesId: trackJson['seriesId'] as String? ?? seriesId,
              seriesTitle: trackJson['seriesTitle'] as String? ?? seriesTitle,
              speaker: trackJson['speaker'] as String? ?? seriesSpeaker,
              durationSeconds: trackJson['durationSeconds'] as int? ?? 0,
              audioUrl: trackJson['audioUrl'] as String,
              streamUrl: trackJson['streamUrl'] as String?,
              fallbackUrl: trackJson['fallbackUrl'] as String?,
              coverUrl: trackJson['coverUrl'] as String?,
              thumbnailUrl: trackJson['thumbnailUrl'] as String?,
              scriptureBook: trackJson['scriptureBook'] as String?,
              scriptureChapter: trackJson['scriptureChapter'] as int?,
              scriptureVerse: trackJson['scriptureVerse'] as int?,
            );
          }).toList(),
        );
        
        await _sqliteAdapter.upsertSeries(series, updatedAtMs: currentMs);
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SqliteAudioCatalogAdapter.syncedPrefKey, true);
      debugPrint('AudioSyncManager: Sync complete.');
    } catch (e) {
      debugPrint('AudioSyncManager Error: $e');
    }
  }
}
