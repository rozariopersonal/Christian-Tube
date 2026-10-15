import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reader theme mode enum.
///
/// Kept here (rather than in the screen) so both the screen and the appearance
/// service agree on a single source of truth.
enum ReaderThemeMode { system, paper, sepia, dark, amoled }

/// Persisted reading-appearance settings.
///
/// Holds the reader's theme, font family, font size, line height, and text formatting
/// (bold, italic, underline) along with their color mappings and SharedPreferences persistence.
/// This is pure logic with **no widget/build dependency**, so it is unit-testable in isolation.
class ReaderAppearance extends ChangeNotifier {
  static const String prefFontSize = 'book_reader_font_size';
  static const String prefSerif = 'book_reader_serif';
  static const String prefFontFamily = 'book_reader_font_family';
  static const String prefThemeMode = 'book_reader_theme_mode';
  static const String prefLineHeight = 'book_reader_line_height';
  static const String prefIsBold = 'reader_is_bold';
  static const String prefIsItalic = 'reader_is_italic';
  static const String prefIsUnderline = 'reader_is_underline';

  static const double _minFontSize = 14.0;
  static const double _maxFontSize = 26.0;

  double _fontSize = 17.0;
  String _fontFamily = 'Playfair';
  ReaderThemeMode _themeMode = ReaderThemeMode.system;
  double _lineHeight = 1.65;
  String _languageCode = 'en';
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;

  double get fontSize => _fontSize;
  String get fontFamily => _fontFamily;
  ReaderThemeMode get themeMode => _themeMode;
  double get lineHeight => _lineHeight;
  double get minFontSize => _minFontSize;
  double get maxFontSize => _maxFontSize;
  String get languageCode => _languageCode;
  bool get isBold => _isBold;
  bool get isItalic => _isItalic;
  bool get isUnderline => _isUnderline;

  FontWeight get fontWeight => _isBold ? FontWeight.bold : FontWeight.normal;
  FontStyle get fontStyle => _isItalic ? FontStyle.italic : FontStyle.normal;
  TextDecoration get textDecoration =>
      _isUnderline ? TextDecoration.underline : TextDecoration.none;

  /// Concrete font family name registered with the Flutter font engine.
  String? get resolvedFontFamily =>
      ScriptureThemeCatalog.resolveFontFamily(_fontFamily, _languageCode);

  bool get usesSystemTheme => _themeMode == ReaderThemeMode.system;

  bool get useSerifFont => _fontFamily == 'Playfair' || _fontFamily == 'serif';

  set useSerifFont(bool value) {
    _fontFamily = value ? 'Playfair' : 'Outfit';
    notifyListeners();
    unawaited(_saveFontFamily(_fontFamily));
  }

  set fontSize(double value) {
    if (value < _minFontSize || value > _maxFontSize) return;
    _fontSize = value;
    notifyListeners();
    unawaited(_saveDouble(prefFontSize, value));
  }

  set fontFamily(String value) {
    _fontFamily = value;
    notifyListeners();
    unawaited(_saveFontFamily(value));
  }

  set languageCode(String value) {
    if (_languageCode == value) return;
    _languageCode = value;
    unawaited(_loadLanguageFontPreference(value));
    notifyListeners();
  }

  set themeMode(ReaderThemeMode value) {
    _themeMode = value;
    notifyListeners();
  }

  set lineHeight(double value) {
    if (value < 1.0 || value > 2.5) return;
    _lineHeight = value;
    notifyListeners();
    unawaited(_saveDouble(prefLineHeight, value));
  }

  set isBold(bool value) {
    if (_isBold == value) return;
    _isBold = value;
    notifyListeners();
    unawaited(_saveBool(prefIsBold, value));
  }

  set isItalic(bool value) {
    if (_isItalic == value) return;
    _isItalic = value;
    notifyListeners();
    unawaited(_saveBool(prefIsItalic, value));
  }

  set isUnderline(bool value) {
    if (_isUnderline == value) return;
    _isUnderline = value;
    notifyListeners();
    unawaited(_saveBool(prefIsUnderline, value));
  }

  static String fontPrefKey(String lang) =>
      'reader_font_family_${ScriptureThemeCatalog.normalizeLanguageCode(lang)}';

  Future<void> _saveFontFamily(String family) async {
    final key = fontPrefKey(_languageCode);
    await _saveString(key, family);
    await _saveString(prefFontFamily, family); // legacy fallback
  }

  Future<void> _loadLanguageFontPreference(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = fontPrefKey(lang);
      final savedFamily = prefs.getString(key);
      if (savedFamily != null && savedFamily.isNotEmpty) {
        _fontFamily = savedFamily;
      } else {
        _fontFamily = ScriptureThemeCatalog.getDefaultFontForLanguage(lang);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Remove any legacy theme mode override so readers always follow the app theme
      if (prefs.containsKey(prefThemeMode)) {
        await prefs.remove(prefThemeMode);
      }

      final savedSize = prefs.getDouble(prefFontSize);
      if (savedSize != null && savedSize >= _minFontSize && savedSize <= _maxFontSize) {
        _fontSize = savedSize;
      }

      final langKey = fontPrefKey(_languageCode);
      final savedLangFont = prefs.getString(langKey);
      if (savedLangFont != null && savedLangFont.isNotEmpty) {
        _fontFamily = savedLangFont;
      } else {
        final savedFontFamily = prefs.getString(prefFontFamily);
        if (savedFontFamily != null && savedFontFamily.isNotEmpty) {
          _fontFamily = savedFontFamily;
        } else {
          final savedSerif = prefs.getBool(prefSerif);
          if (savedSerif != null) {
            _fontFamily = savedSerif ? 'Playfair' : 'Outfit';
          }
        }
      }

      final savedLineHeight = prefs.getDouble(prefLineHeight);
      if (savedLineHeight != null && savedLineHeight >= 1.0 && savedLineHeight <= 2.5) {
        _lineHeight = savedLineHeight;
      }

      _isBold = prefs.getBool(prefIsBold) ?? false;
      _isItalic = prefs.getBool(prefIsItalic) ?? false;
      _isUnderline = prefs.getBool(prefIsUnderline) ?? false;
    } catch (_) {}
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (_) {}
  }

  Future<void> _saveString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  bool isDark(AppTokens tokens) => tokens.isDark;

  Color background(AppTokens tokens) => tokens.background;

  Color surface(AppTokens tokens) => tokens.surface;

  Color surfaceVariant(AppTokens tokens) => tokens.surfaceVariant;

  Color surfaceBorder(AppTokens tokens) => tokens.surfaceBorder;

  Color textColor(AppTokens tokens) => tokens.onSurface;

  Color mutedTextColor(AppTokens tokens) => tokens.onSurfaceMuted;

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
