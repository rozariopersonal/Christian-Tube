import 'language_meta.dart';

/// Provides the localized native script name (in its own language) for Bible versions
/// and catalog languages (e.g. `தமிழ்`, `हिन्दी`, `English`, `Deutsch`, `日本語`).
class BibleVersionNativeNames {
  BibleVersionNativeNames._();

  /// Direct overrides for version IDs that map to specific languages/scripts.
  static const Map<String, String> _versionIdToNativeScript = {
    // Tamil
    'TAOBVSI': 'தமிழ்',
    'TAM_TCV': 'தமிழ்',

    // Hindi
    'HIN_IRV': 'हिन्दी',
    'HIN_HCV': 'हिन्दी',

    // Malayalam
    'MAL_IRV': 'മലയാളം',
    'MAL_MCV': 'മലയാളം',
    'MAL1910': 'മലയാളം',

    // Telugu
    'TEL_IRV': 'తెలుగు',
    'TEL_TCV': 'తెలుగు',

    // Kannada
    'KAN_IRV': 'ಕನ್ನಡ',
    'KAN_KCV': 'ಕನ್ನಡ',

    // Other Indian languages
    'BEN_BCV': 'বাংলা',
    'MAR_MCV': 'मराठी',
    'GUJ_IRV': 'ગુજરાતી',
    'PUN_IRV': 'ਪੰਜਾਬੀ',
    'PAN_PCV': 'ਪੰਜਾਬੀ',
    'ORI_IRV': 'ଓଡ଼ିଆ',
    'ASM_IRV': 'অসমীয়া',
    'URD_UCV': 'اردو',

    // European & Global
    'LUTHER1545': 'Deutsch',
    'ELBERFELDER1905': 'Deutsch',
    'ELBERFELDER': 'Deutsch',
    'SSE': 'Español',
    'MARTIN': 'Français',
    'RIVEDUTA': 'Italiano',
    'DIODATI': 'Italiano',
    'STATENVERTALING': 'Nederlands',
    'POLGDANSKA': 'Polski',
    'KAROLI': 'Magyar',
    'SWEDISH': 'Svenska',
    'DANISH': 'Dansk',
    'PYHAAMATTU1933': 'Suomi',
    'BKR': 'Čeština',
    'CROATIA': 'Hrvatski',
    'ALB': 'Shqip',
    'KOREAN': '한국어',
    'VIETNAMESE': 'Tiếng Việt',
    'CUT': '中文',
    'JAPKOUGO': '日本語',
    'TAGALOG': 'Tagalog',
    'ESPERANTO': 'Esperanto',

    // English
    'NASB': 'English',
    'NLT': 'English',
    'MSG': 'English',
    'NIV': 'English',
    'AMP': 'English',
    'BSB': 'English',
    'WEB': 'English',
    'KJV': 'English',
    'ASV': 'English',
    'BBE': 'English',
    'YLT': 'English',
    'WB': 'English',
  };

  /// Fallback language name to native script.
  static const Map<String, String> _languageNameToNativeScript = {
    'tamil': 'தமிழ்',
    'hindi': 'हिन्दी',
    'malayalam': 'മലയാളം',
    'telugu': 'తెలుగు',
    'kannada': 'ಕನ್ನಡ',
    'bengali': 'বাংলা',
    'gujarati': 'ગુજરાતી',
    'marathi': 'मराठी',
    'punjabi': 'ਪੰਜਾਬੀ',
    'odia': 'ଓଡ଼ିଆ',
    'assamese': 'অসমীয়া',
    'urdu': 'اردو',
    'nepali': 'नेपाली',
    'sinhala': 'සිංහල',
    'german': 'Deutsch',
    'spanish': 'Español',
    'french': 'Français',
    'italian': 'Italiano',
    'dutch': 'Nederlands',
    'polish': 'Polski',
    'russian': 'Русский',
    'hungarian': 'Magyar',
    'swedish': 'Svenska',
    'danish': 'Dansk',
    'finnish': 'Suomi',
    'czech': 'Čeština',
    'croatian': 'Hrvatski',
    'albanian': 'Shqip',
    'japanese': '日本語',
    'korean': '한국어',
    'chinese': '中文',
    'tagalog': 'Tagalog',
    'vietnamese': 'Tiếng Việt',
    'esperanto': 'Esperanto',
    'english': 'English',
  };

  /// Resolves the native language script for a given [versionId].
  ///
  /// Checks the direct catalog map first, then resolves through [language] and
  /// [languageCode] using [LanguageMeta].
  static String getNativeScript(
    String versionId, {
    String? language,
    String? languageCode,
  }) {
    final upperId = versionId.trim().toUpperCase();
    final direct = _versionIdToNativeScript[upperId];
    if (direct != null && direct.isNotEmpty) return direct;

    if (language != null && language.trim().isNotEmpty) {
      final byLang = _languageNameToNativeScript[language.trim().toLowerCase()];
      if (byLang != null && byLang.isNotEmpty) return byLang;
    }

    if (languageCode != null && languageCode.trim().isNotEmpty) {
      final meta = LanguageMeta.fromCode(languageCode.trim());
      if (meta.nativeName.isNotEmpty) return meta.nativeName;
    }

    if (language != null && language.trim().isNotEmpty) {
      final meta = LanguageMeta.fromCode(language.trim());
      if (meta.nativeName.isNotEmpty) return meta.nativeName;
      return language.trim();
    }

    return '';
  }
}
