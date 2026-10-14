import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent history of recently used Bible translations.
///
/// Stores version IDs in order of recency (most recently used first).
class BibleRecentVersionsService {
  static const String keyRecentVersions = 'bible_recent_versions';
  static const int defaultMaxRecents = 10;

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

  /// Records [versionId] as the most recently accessed translation.
  /// Moves [versionId] to the top of the list, de-duplicates case-insensitively,
  /// and persists up to [maxRecents] items.
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
    return current;
  }

  /// Clears the recent versions history.
  Future<void> clearRecentVersions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyRecentVersions);
  }
}
