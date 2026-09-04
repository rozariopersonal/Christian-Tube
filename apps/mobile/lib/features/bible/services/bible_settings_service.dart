import 'package:shared_preferences/shared_preferences.dart';
import '../models/bible_settings.dart';

class BibleSettingsService {
  static const String _keyExpandCrossReferences =
      'bible_expand_cross_references';
  static const String _keyLastVersion = 'bible_last_version';
  static const String _keyLastBook = 'bible_last_book';
  static const String _keyLastChapter = 'bible_last_chapter';
  static const String _keyHasProgress = 'bible_has_progress';

  Future<BibleSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return BibleSettings(
      expandCrossReferences: prefs.getBool(_keyExpandCrossReferences) ?? false,
      lastVersion: prefs.getString(_keyLastVersion),
      lastBook: prefs.getBool(_keyHasProgress) ?? false
          ? prefs.getString(_keyLastBook)
          : null,
      lastChapter: prefs.getInt(_keyLastChapter) ?? 1,
    );
  }

  Future<void> saveSettings(BibleSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
        _keyExpandCrossReferences, settings.expandCrossReferences);
    await prefs.setBool(_keyHasProgress, settings.hasProgress);
    if (settings.lastVersion != null) {
      await prefs.setString(_keyLastVersion, settings.lastVersion!);
    }
    if (settings.lastBook != null) {
      await prefs.setString(_keyLastBook, settings.lastBook!);
    }
    await prefs.setInt(_keyLastChapter, settings.lastChapter);
  }

  /// Saves the user's current reading location so they can resume later.
  Future<void> saveReadingProgress(
    String versionId,
    String book,
    int chapter,
  ) async {
    final current = await loadSettings();
    return saveSettings(
      current.copyWith(
        lastVersion: versionId,
        lastBook: book,
        lastChapter: chapter,
      ),
    );
  }
}
