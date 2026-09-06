import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_track.dart';

/// Immutable container holding restored playback state across sessions and devices.
@immutable
class StoredPlaybackState {
  final AudioTrack track;
  final int positionSeconds;
  final List<AudioTrack> queue;
  final int queueIndex;
  final DateTime updatedAt;

  const StoredPlaybackState({
    required this.track,
    required this.positionSeconds,
    this.queue = const [],
    this.queueIndex = 0,
    required this.updatedAt,
  });
}

/// Persists audio playback position, history, active queue, and timestamps
/// to ensure deterministic playback resumption across app sessions and devices.
class AudioStorageService {
  static const _lastTrackKey = 'audio_last_track_json';
  static const _positionPrefix = 'audio_pos_';
  static const _posUpdatedAtPrefix = 'audio_pos_updated_at_';
  static const _lastPlaybackUpdatedAtKey = 'audio_playback_updated_at';
  static const _lastQueueKey = 'audio_last_queue_json';
  static const _lastQueueIndexKey = 'audio_last_queue_index';
  static const _historyKey = 'audio_history_ids';

  /// Saves the playback position in seconds for [trackId], with an ISO timestamp.
  Future<void> savePosition(
    String trackId,
    int seconds, {
    DateTime? updatedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveTime = updatedAt ?? DateTime.now().toUtc();
    await prefs.setInt('$_positionPrefix$trackId', seconds);
    await prefs.setString(
      '$_posUpdatedAtPrefix$trackId',
      effectiveTime.toIso8601String(),
    );
  }

  /// Gets the saved position in seconds for [trackId], defaulting to 0.
  Future<int> getPosition(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_positionPrefix$trackId') ?? 0;
  }

  /// Gets the timestamp when [trackId]'s position was last persisted.
  Future<DateTime?> getPositionUpdatedAt(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_posUpdatedAtPrefix$trackId');
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Atomically saves the complete playback session state: active track, playhead position,
  /// optional surrounding playlist queue, and updated timestamp.
  Future<void> savePlaybackState({
    required AudioTrack track,
    required int positionSeconds,
    List<AudioTrack>? queue,
    int? queueIndex,
    DateTime? updatedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveTime = updatedAt ?? DateTime.now().toUtc();

    // 1. Save track JSON & timestamp
    await prefs.setString(_lastTrackKey, jsonEncode(track.toJson()));
    await prefs.setString(
      _lastPlaybackUpdatedAtKey,
      effectiveTime.toIso8601String(),
    );

    // 2. Save position
    await prefs.setInt('$_positionPrefix${track.id}', positionSeconds);
    await prefs.setString(
      '$_posUpdatedAtPrefix${track.id}',
      effectiveTime.toIso8601String(),
    );

    // 3. Save queue if provided
    if (queue != null && queue.isNotEmpty) {
      final queueJson = jsonEncode(queue.map((t) => t.toJson()).toList());
      await prefs.setString(_lastQueueKey, queueJson);
      await prefs.setInt(_lastQueueIndexKey, queueIndex ?? 0);
    }

    // 4. Update history
    final history = prefs.getStringList(_historyKey) ?? [];
    history.remove(track.id);
    history.insert(0, track.id);
    if (history.length > 50) history.removeLast();
    await prefs.setStringList(_historyKey, history);
  }

  /// Restores the complete playback session state if one was previously persisted.
  Future<StoredPlaybackState?> getLastPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final trackJsonStr = prefs.getString(_lastTrackKey);
    if (trackJsonStr == null || trackJsonStr.isEmpty) return null;

    try {
      final trackMap = jsonDecode(trackJsonStr) as Map<String, dynamic>;
      final track = AudioTrack.fromJson(trackMap);
      final pos = prefs.getInt('$_positionPrefix${track.id}') ?? 0;

      final updatedRaw = prefs.getString(_lastPlaybackUpdatedAtKey);
      final updatedAt = (updatedRaw != null && updatedRaw.isNotEmpty)
          ? DateTime.tryParse(updatedRaw) ?? DateTime.now().toUtc()
          : DateTime.now().toUtc();

      // Restore queue
      List<AudioTrack> queue = [track];
      int queueIdx = 0;
      final queueJsonStr = prefs.getString(_lastQueueKey);
      if (queueJsonStr != null && queueJsonStr.isNotEmpty) {
        try {
          final list = jsonDecode(queueJsonStr) as List<dynamic>;
          queue = list
              .map((item) => AudioTrack.fromJson(item as Map<String, dynamic>))
              .toList();
          queueIdx = prefs.getInt(_lastQueueIndexKey) ?? 0;
          if (queueIdx < 0 || queueIdx >= queue.length) queueIdx = 0;
        } catch (_) {}
      }

      return StoredPlaybackState(
        track: track,
        positionSeconds: pos,
        queue: queue,
        queueIndex: queueIdx,
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves the track currently being listened to along with history.
  Future<void> saveLastTrack(AudioTrack track) async {
    final currentPos = await getPosition(track.id);
    await savePlaybackState(
      track: track,
      positionSeconds: currentPos,
    );
  }

  /// Returns the last listened track, if any.
  Future<AudioTrack?> getLastTrack() async {
    final state = await getLastPlaybackState();
    return state?.track;
  }

  /// Returns timestamp of last track update.
  Future<DateTime?> getLastTrackUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastPlaybackUpdatedAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
