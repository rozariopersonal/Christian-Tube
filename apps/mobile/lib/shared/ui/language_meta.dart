/// Renders an item noun agreeing with [count], assuming [pluralNoun] is the
/// plural form (e.g. 'items', 'books'). Falls back to the plural for irregular
/// nouns (e.g. 'series').
String countNoun(String pluralNoun, int count) {
  if (count == 1 && pluralNoun.length > 1 && pluralNoun.endsWith('s')) {
    return pluralNoun.substring(0, pluralNoun.length - 1);
  }
  return pluralNoun;
}

/// Metadata describing a supported catalog language.
///
/// Shared by every content type in the library (books, songs, articles,
/// audio) so a single language registry can be filtered and displayed
/// uniformly across the app.
class LanguageMeta {
  final String code;
  final String englishName;
  final String nativeName;

  const LanguageMeta({
    required this.code,
    required this.englishName,
    required this.nativeName,
  });

  /// Display label showing native name if different from English name.
  String get displayName {
    if (code.toLowerCase() == 'all') return englishName;
    if (nativeName.isNotEmpty && nativeName != englishName) {
      return '$englishName ($nativeName)';
    }
    return englishName;
  }

  /// Compact label for pills or small spaces.
  String get shortLabel {
    if (code.toLowerCase() == 'all') return 'All';
    return englishName;
  }

  static const Map<String, LanguageMeta> supportedLanguages = {
    'all': LanguageMeta(code: 'All', englishName: 'All Languages', nativeName: 'All'),
    'en': LanguageMeta(code: 'en', englishName: 'English', nativeName: 'English'),
    'ta': LanguageMeta(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்'),
    'hi': LanguageMeta(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
    'te': LanguageMeta(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు'),
    'kn': LanguageMeta(code: 'kn', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    'ml': LanguageMeta(code: 'ml', englishName: 'Malayalam', nativeName: 'മലയാളം'),
    'de': LanguageMeta(code: 'de', englishName: 'German', nativeName: 'Deutsch'),
    'ro': LanguageMeta(code: 'ro', englishName: 'Romanian', nativeName: 'Română'),
    'pt': LanguageMeta(code: 'pt', englishName: 'Portuguese', nativeName: 'Português'),
    'si': LanguageMeta(code: 'si', englishName: 'Sinhala', nativeName: 'සිංහල'),
    'es': LanguageMeta(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
    'fr': LanguageMeta(code: 'fr', englishName: 'French', nativeName: 'Français'),
    'pl': LanguageMeta(code: 'pl', englishName: 'Polish', nativeName: 'Polski'),
    'ru': LanguageMeta(code: 'ru', englishName: 'Russian', nativeName: 'Русский'),
    'mr': LanguageMeta(code: 'mr', englishName: 'Marathi', nativeName: 'मराठी'),
  };

  /// Resolves metadata for a language code or full name (case-insensitive).
  static LanguageMeta fromCode(String code) {
    final lower = code.trim().toLowerCase();
    final meta = supportedLanguages[lower];
    if (meta != null) return meta;
    for (final m in supportedLanguages.values) {
      if (m.englishName.toLowerCase() == lower ||
          m.nativeName.toLowerCase() == lower) {
        return m;
      }
    }
    return LanguageMeta(
      code: code,
      englishName: code.toUpperCase(),
      nativeName: code.toUpperCase(),
    );
  }
}
