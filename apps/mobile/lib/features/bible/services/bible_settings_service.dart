import 'package:shared_preferences/shared_preferences.dart';
import '../models/bible_settings.dart';

class BibleSettingsService {
  static const String _keyFontSize = 'bible_font_size';
  static const String _keyLineHeight = 'bible_line_height';
  static const String _keyDarkMode = 'bible_dark_mode';

  Future<BibleSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return BibleSettings(
      fontSize: prefs.getDouble(_keyFontSize) ?? 18.0,
      lineHeight: prefs.getDouble(_keyLineHeight) ?? 1.6,
      isDarkMode: prefs.getBool(_keyDarkMode) ?? false,
    );
  }

  Future<void> saveSettings(BibleSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, settings.fontSize);
    await prefs.setDouble(_keyLineHeight, settings.lineHeight);
    await prefs.setBool(_keyDarkMode, settings.isDarkMode);
  }
}
