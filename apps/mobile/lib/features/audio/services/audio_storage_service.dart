import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_track.dart';

/// Persists audio playback position and history.
class AudioStorageService {
  static const _lastTrackKey = 'audio_last_track_json';
  static const _positionPrefix = 'audio_pos_';
  static const _historyKey = 'audio_history_ids';

  /// Saves the last position in seconds for [trackId].
  Future<void> savePosition(String trackId, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_positionPrefix$trackId', seconds);
  }

  /// Gets the saved position in seconds for [trackId], defaulting to 0.
  Future<int> getPosition(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_positionPrefix$trackId') ?? 0;
  }

  /// Saves the track currently being listened to along with history.
  Future<void> saveLastTrack(AudioTrack track) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTrackKey, jsonEncode(track.toJson()));

    // Record in history list
    final history = prefs.getStringList(_historyKey) ?? [];
    history.remove(track.id);
    history.insert(0, track.id);
    if (history.length > 50) history.removeLast();
    await prefs.setStringList(_historyKey, history);
  }

  /// Returns the last listened track, if any.
  Future<AudioTrack?> getLastTrack() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_lastTrackKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AudioTrack.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
