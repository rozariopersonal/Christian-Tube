import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reader theme mode enum.
///
/// Kept here (rather than in the screen) so both the screen and the appearance
/// service agree on a single source of truth.
enum ReaderThemeMode { system, paper, sepia, dark, amoled }

/// Persisted reading-appearance settings.
///
/// Holds the reader's theme, font family, font size, and line height along with
/// their color mappings and SharedPreferences persistence. This is pure logic
/// with **no widget/build dependency**, so it is unit-testable in isolation.
class ReaderAppearance extends ChangeNotifier {
  static const String prefFontSize = 'book_reader_font_size';
  static const String prefSerif = 'book_reader_serif';
  static const String prefThemeMode = 'book_reader_theme_mode';
  static const String prefLineHeight = 'book_reader_line_height';

  static const double _minFontSize = 14.0;
  static const double _maxFontSize = 26.0;

  double _fontSize = 17.0;
  bool _useSerifFont = true;
  ReaderThemeMode _themeMode = ReaderThemeMode.system;
  double _lineHeight = 1.65;

  double get fontSize => _fontSize;
  bool get useSerifFont => _useSerifFont;
  ReaderThemeMode get themeMode => _themeMode;
  double get lineHeight => _lineHeight;
  double get minFontSize => _minFontSize;
  double get maxFontSize => _maxFontSize;

  bool get usesSystemTheme => _themeMode == ReaderThemeMode.system;

  set fontSize(double value) {
    if (value < _minFontSize || value > _maxFontSize) return;
    _fontSize = value;
    notifyListeners();
    unawaited(_saveDouble(prefFontSize, value));
  }

  set useSerifFont(bool value) {
    _useSerifFont = value;
    notifyListeners();
    unawaited(_saveBool(prefSerif, value));
  }

  set themeMode(ReaderThemeMode value) {
    _themeMode = value;
    notifyListeners();
    unawaited(_saveThemeMode());
  }

  set lineHeight(double value) {
    if (value < 1.0 || value > 2.5) return;
    _lineHeight = value;
    notifyListeners();
    unawaited(_saveDouble(prefLineHeight, value));
  }

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSize = prefs.getDouble(prefFontSize);
      if (savedSize != null && savedSize >= _minFontSize && savedSize <= _maxFontSize) {
        _fontSize = savedSize;
      }
      final savedSerif = prefs.getBool(prefSerif);
      if (savedSerif != null) {
        _useSerifFont = savedSerif;
      }
      final savedTheme = prefs.getString(prefThemeMode);
      if (savedTheme != null) {
        _themeMode = ReaderThemeMode.values.firstWhere(
          (m) => m.name == savedTheme,
          orElse: () => ReaderThemeMode.system,
        );
      }
      final savedLineHeight = prefs.getDouble(prefLineHeight);
      if (savedLineHeight != null && savedLineHeight >= 1.0 && savedLineHeight <= 2.5) {
        _lineHeight = savedLineHeight;
      }
    } catch (_) {}
  }

  Future<void> _saveThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefThemeMode, _themeMode.name);
    } catch (_) {}
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (_) {}
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Color background(AppTokens tokens) {
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFFFAF9F6);
      case ReaderThemeMode.sepia:
        return const Color(0xFFFBF0D9);
      case ReaderThemeMode.dark:
        return const Color(0xFF1E212B);
      case ReaderThemeMode.amoled:
        return const Color(0xFF000000);
      case ReaderThemeMode.system:
        return tokens.background;
    }
  }

  Color textColor(AppTokens tokens) {
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFF1A1A1A);
      case ReaderThemeMode.sepia:
        return const Color(0xFF3B2F2F);
      case ReaderThemeMode.dark:
        return const Color(0xFFE6EDF3);
      case ReaderThemeMode.amoled:
        return const Color(0xFFFFFFFF);
      case ReaderThemeMode.system:
        return tokens.onSurface;
    }
  }

  Color surfaceVariant(AppTokens tokens) {
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFFF0EFEA);
      case ReaderThemeMode.sepia:
        return const Color(0xFFF0E4C9);
      case ReaderThemeMode.dark:
        return const Color(0xFF282B37);
      case ReaderThemeMode.amoled:
        return const Color(0xFF141414);
      case ReaderThemeMode.system:
        return tokens.surfaceVariant;
    }
  }

  Color mutedTextColor(AppTokens tokens) {
    switch (_themeMode) {
      case ReaderThemeMode.paper:
        return const Color(0xFF6B6860);
      case ReaderThemeMode.sepia:
        return const Color(0xFF7A685B);
      case ReaderThemeMode.dark:
        return const Color(0xFF9EA7B3);
      case ReaderThemeMode.amoled:
        return const Color(0xFFA0A0A0);
      case ReaderThemeMode.system:
        return tokens.onSurfaceMuted;
    }
  }

  /// Maps a highlight [colorIndex] (0..3) to its rendered [Color].
  static Color highlightColorByIndex(int colorIndex) {
    switch (colorIndex) {
      case 1:
        return const Color(0xFF81C784); // Green
      case 2:
        return const Color(0xFF64B5F6); // Blue
      case 3:
        return const Color(0xFFF48FB1); // Pink
      case 0:
      default:
        return const Color(0xFFFFD54F); // Amber / Yellow
    }
  }
}
