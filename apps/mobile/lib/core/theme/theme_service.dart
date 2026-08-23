import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

enum AppColorTheme {
  blue(name: 'Sapphire Blue', color: Color(0xFF3B82F6)),
  red(name: 'Royal Crimson', color: Color(0xFFDC2626)),
  green(name: 'Emerald Green', color: Color(0xFF10B981)),
  purple(name: 'Violet Purple', color: Color(0xFF8B5CF6)),
  amber(name: 'Warm Amber', color: Color(0xFFF59E0B)),
  pink(name: 'Rose Pink', color: Color(0xFFEC4899)),
  teal(name: 'Cyan Teal', color: Color(0xFF06B6D4));

  final String name;
  final Color color;
  const AppColorTheme({required this.name, required this.color});
}

class ThemeService extends ChangeNotifier {
  static const String _themePrefKey = 'theme_mode_preference';
  static const String _colorThemeKey = 'theme_color_preference';
  static const String _fontFamilyKey = 'theme_font_family';
  static const String _languageKey = 'app_language_preference';
  static const String _amoledKey = 'theme_amoled_mode';

  ThemeMode _themeMode = ThemeMode.system;
  AppColorTheme _colorTheme = AppColorTheme.blue;
  String _fontFamily = 'Inter';
  String _languageCode = 'en';
  bool _isAmoled = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  AppColorTheme get colorTheme => _colorTheme;
  String get fontFamily => _fontFamily;
  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  bool get isAmoled => _isAmoled;

  ThemeService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Theme Mode
    final savedMode = prefs.getString(_themePrefKey);
    if (savedMode == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (savedMode == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }

    // Color Theme
    final savedColor = prefs.getString(_colorThemeKey);
    if (savedColor != null) {
      _colorTheme = AppColorTheme.values.firstWhere(
        (c) => c.name == savedColor || c.toString() == savedColor,
        orElse: () => AppColorTheme.blue,
      );
    }

    // Font Family
    _fontFamily = prefs.getString(_fontFamilyKey) ?? 'Inter';

    // Language
    _languageCode = prefs.getString(_languageKey) ?? 'en';

    // AMOLED Mode
    _isAmoled = prefs.getBool(_amoledKey) ?? false;

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.dark) {
      await prefs.setString(_themePrefKey, 'dark');
    } else if (mode == ThemeMode.light) {
      await prefs.setString(_themePrefKey, 'light');
    } else {
      await prefs.setString(_themePrefKey, 'system');
    }
  }

  Future<void> setColorTheme(AppColorTheme theme) async {
    _colorTheme = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorThemeKey, theme.name);
  }

  Future<void> setFontFamily(String font) async {
    _fontFamily = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontFamilyKey, font);
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  Future<void> setAmoled(bool enabled) async {
    _isAmoled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_amoledKey, enabled);
  }

  TextTheme _getTextTheme(TextTheme base) {
    switch (_fontFamily) {
      case 'Outfit':
        return GoogleFonts.outfitTextTheme(base);
      case 'Roboto':
        return GoogleFonts.robotoTextTheme(base);
      case 'Poppins':
        return GoogleFonts.poppinsTextTheme(base);
      case 'Nunito':
        return GoogleFonts.nunitoTextTheme(base);
      case 'Playfair Display':
        return GoogleFonts.playfairDisplayTextTheme(base);
      case 'Inter':
      default:
        return GoogleFonts.interTextTheme(base);
    }
  }

  ThemeData get lightTheme {
    final primaryColor = _colorTheme.color;
    final accentColor = AppConfig.accentColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        secondary: accentColor,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      textTheme: _getTextTheme(ThemeData.light().textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.black54,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  ThemeData get darkTheme {
    final primaryColor = _colorTheme.color;
    final accentColor = AppConfig.accentColor;
    final bgColor = _isAmoled ? Colors.black : const Color(0xFF0F172A);
    final cardColor = _isAmoled ? const Color(0xFF121212) : const Color(0xFF1E293B);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryColor,
        secondary: accentColor,
        surface: cardColor,
      ),
      scaffoldBackgroundColor: bgColor,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      textTheme: _getTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: bgColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bgColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white60,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
