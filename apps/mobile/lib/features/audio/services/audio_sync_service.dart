import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/models/user.dart';
import '../models/audio_track.dart';

/// Represents a playback record synchronized with the backend.
class RemotePlaybackRecord {
  final AudioTrack track;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime updatedAt;

  const RemotePlaybackRecord({
    required this.track,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
  });
}

/// Orchestrates cross-device playback state synchronization with the backend API.
///
/// Ensures that progress made on one device (e.g. phone) seamlessly syncs to another
/// device (e.g. tablet or web) when signed in with the same user account.
class AudioSyncService {
  static final AudioSyncService instance = AudioSyncService();

  final ApiClient _apiClient = ApiClient();
  DateTime? _lastPushTimestamp;
  String? _lastPushedTrackId;
  int? _lastPushedPosition;

  /// Retrieves the current logged-in user email if available.
  Future<String?> _getUserEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('current_user');
      if (userJson != null && userJson.isNotEmpty) {
        final user = User.fromJson(jsonDecode(userJson));
        if (user.email.isNotEmpty) return user.email.trim().toLowerCase();
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves current logged-in user ID if available.
  Future<String?> _getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('current_user');
      if (userJson != null && userJson.isNotEmpty) {
        final user = User.fromJson(jsonDecode(userJson));
        if (user.id.isNotEmpty) return user.id;
      }
    } catch (_) {}
    return null;
  }

  /// Pushes current playback progress to the cloud.
  /// Throttled automatically to prevent excessive network spam during active playback.
  Future<void> pushPlayback({
    required AudioTrack track,
    required int positionSeconds,
    required int durationSeconds,
    bool force = false,
    DateTime? updatedAt,
  }) async {
    final email = await _getUserEmail();
    if (email == null || email.isEmpty) return; // Sync requires user identity

    final now = updatedAt ?? DateTime.now().toUtc();

    // Debounce/throttle non-forced updates (minimum 10 seconds between pushes unless track changed)
    if (!force &&
        _lastPushedTrackId == track.id &&
        _lastPushTimestamp != null &&
        now.difference(_lastPushTimestamp!).inSeconds < 10 &&
        _lastPushedPosition != null &&
        (positionSeconds - _lastPushedPosition!).abs() < 10) {
      return;
    }

    _lastPushedTrackId = track.id;
    _lastPushTimestamp = now;
    _lastPushedPosition = positionSeconds;

    try {
      final userId = await _getUserId();
      await _apiClient.dio.post(
        '/user/playback',
        data: {
          'userEmail': email,
          'userId': userId,
          'mediaType': 'audio',
          'trackId': track.id,
          'seriesId': track.seriesId,
          'title': track.title,
          'speaker': track.speaker,
          'coverUrl': track.coverUrl,
          'audioUrl': track.audioUrl,
          'positionSeconds': positionSeconds,
          'durationSeconds': durationSeconds,
          'payloadJson': jsonEncode(track.toJson()),
          'updatedAt': now.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('AudioSyncService pushPlayback non-blocking warning: $e');
    }
  }

  /// Pulls the latest playback progress from the cloud for the current user.
  /// Returns [RemotePlaybackRecord] if a newer record exists on the cloud.
  Future<RemotePlaybackRecord?> pullPlayback() async {
    final email = await _getUserEmail();
    if (email == null || email.isEmpty) return null;

    try {
      final userId = await _getUserId();
      final response = await _apiClient.dio.get(
        '/user/playback',
        queryParameters: {
          'email': email,
          if (userId != null) 'userId': userId,
          'mediaType': 'audio',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final trackId = data['trackId'] as String?;
        if (trackId == null || trackId.isEmpty) return null;

        AudioTrack? track;
        final payloadJson = data['payloadJson'] as String?;
        if (payloadJson != null && payloadJson.isNotEmpty) {
          try {
            final map = jsonDecode(payloadJson) as Map<String, dynamic>;
            track = AudioTrack.fromJson(map);
          } catch (_) {}
        }

        // Fallback reconstruction if payloadJson was unavailable
        track ??= AudioTrack(
          id: trackId,
          title: data['title'] as String? ?? 'Audio Sermon',
          seriesId: data['seriesId'] as String? ?? 'cfc_series',
          seriesTitle: 'CFC Audio Library',
          speaker: data['speaker'] as String? ?? 'Zac Poonen',
          durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
          audioUrl: data['audioUrl'] as String? ?? '',
          coverUrl: data['coverUrl'] as String?,
        );

        final posSec = (data['positionSeconds'] as num?)?.toInt() ?? 0;
        final durSec = (data['durationSeconds'] as num?)?.toInt() ?? track.durationSeconds;

        final rawUpdated = data['updatedAt'] as String?;
        final updatedAt = rawUpdated != null
            ? DateTime.tryParse(rawUpdated) ?? DateTime.now().toUtc()
            : DateTime.now().toUtc();

        return RemotePlaybackRecord(
          track: track,
          positionSeconds: posSec,
          durationSeconds: durSec,
          updatedAt: updatedAt,
        );
      }
    } catch (e) {
      debugPrint('AudioSyncService pullPlayback non-blocking warning: $e');
    }
    return null;
  }
}
