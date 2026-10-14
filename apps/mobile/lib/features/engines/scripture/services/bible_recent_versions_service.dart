import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent history and frequency of used Bible translations.
///
/// Stores version IDs in order of recency (most recently used first)
/// and tracks access counts to provide frequently used translations.
class BibleRecentVersionsService {
  static const String keyRecentVersions = 'bible_recent_versions';
  static const String keyVersionFrequency = 'bible_version_frequency';
  static const int defaultMaxRecents = 10;
  static const int defaultMaxFrequent = 5;

  static final BibleRecentVersionsService _instance =
      BibleRecentVersionsService._internal();
  factory BibleRecentVersionsService() => _instance;
  BibleRecentVersionsService._internal();

  /// Returns the list of recently used version IDs in chronological order (most recent first).
  Future<List<String>> getRecentVersions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(keyRecentVersions);
    return list != null ? List<String>.from(list) : <String>[];
  }

  /// Returns the map of uppercase version ID to usage frequency count.
  Future<Map<String, int>> getFrequencyMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyVersionFrequency);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k.toUpperCase(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Returns the list of frequently used version IDs, sorted descending by usage count.
  /// Only includes versions with usage count > 0, capped at [maxFrequent].
  Future<List<String>> getFrequentlyUsedVersions({
    int maxFrequent = defaultMaxFrequent,
  }) async {
    final freqMap = await getFrequencyMap();
    if (freqMap.isEmpty) return <String>[];

    final recents = await getRecentVersions();
    final entries = freqMap.entries.toList();

    // Sort descending by frequency count; ties broken by recency
    entries.sort((a, b) {
      final diff = b.value.compareTo(a.value);
      if (diff != 0) return diff;
      final idxA = recents.indexWhere((id) => id.toUpperCase() == a.key);
      final idxB = recents.indexWhere((id) => id.toUpperCase() == b.key);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      return a.key.compareTo(b.key);
    });

    return entries.map((e) => e.key).take(maxFrequent).toList();
  }

  /// Records [versionId] as accessed.
  /// Updates the recent order (moves [versionId] to front) and increments its frequency counter.
  Future<List<String>> recordRecentVersion(
    String versionId, {
    int maxRecents = defaultMaxRecents,
  }) async {
    final cleanId = versionId.trim();
    if (cleanId.isEmpty) return await getRecentVersions();

    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(keyRecentVersions) ?? <String>[]).toList();

    // Remove existing match case-insensitively
    current.removeWhere((id) => id.toUpperCase() == cleanId.toUpperCase());
    // Insert at front
    current.insert(0, cleanId);

    if (current.length > maxRecents) {
      current.removeRange(maxRecents, current.length);
    }

    await prefs.setStringList(keyRecentVersions, current);

    // Increment frequency
    final freqMap = await getFrequencyMap();
    final upper = cleanId.toUpperCase();
    freqMap[upper] = (freqMap[upper] ?? 0) + 1;
    await prefs.setString(keyVersionFrequency, jsonEncode(freqMap));

    return current;
  }

  /// Clears recent versions and frequency history.
  Future<void> clearRecentVersions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyRecentVersions);
    await prefs.remove(keyVersionFrequency);
  }
}
