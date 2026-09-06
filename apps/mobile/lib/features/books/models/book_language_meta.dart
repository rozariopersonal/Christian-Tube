/// Metadata describing a supported book language.
class BookLanguageMeta {
  final String code;
  final String englishName;
  final String nativeName;

  const BookLanguageMeta({
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

  static const Map<String, BookLanguageMeta> supportedLanguages = {
    'all': BookLanguageMeta(code: 'All', englishName: 'All Languages', nativeName: 'All'),
    'en': BookLanguageMeta(code: 'en', englishName: 'English', nativeName: 'English'),
    'ta': BookLanguageMeta(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்'),
    'hi': BookLanguageMeta(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
    'te': BookLanguageMeta(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు'),
    'kn': BookLanguageMeta(code: 'kn', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    'ml': BookLanguageMeta(code: 'ml', englishName: 'Malayalam', nativeName: 'മലയാളം'),
    'de': BookLanguageMeta(code: 'de', englishName: 'German', nativeName: 'Deutsch'),
    'ro': BookLanguageMeta(code: 'ro', englishName: 'Romanian', nativeName: 'Română'),
    'pt': BookLanguageMeta(code: 'pt', englishName: 'Portuguese', nativeName: 'Português'),
    'si': BookLanguageMeta(code: 'si', englishName: 'Sinhala', nativeName: 'සිංහල'),
    'es': BookLanguageMeta(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
    'fr': BookLanguageMeta(code: 'fr', englishName: 'French', nativeName: 'Français'),
    'pl': BookLanguageMeta(code: 'pl', englishName: 'Polish', nativeName: 'Polski'),
    'ru': BookLanguageMeta(code: 'ru', englishName: 'Russian', nativeName: 'Русский'),
    'mr': BookLanguageMeta(code: 'mr', englishName: 'Marathi', nativeName: 'मराठी'),
  };

  /// Resolves metadata for a language code or full name (case-insensitive).
  static BookLanguageMeta fromCode(String code) {
    final lower = code.trim().toLowerCase();
    final meta = supportedLanguages[lower];
    if (meta != null) return meta;
    for (final m in supportedLanguages.values) {
      if (m.englishName.toLowerCase() == lower || m.nativeName.toLowerCase() == lower) {
        return m;
      }
    }
    return BookLanguageMeta(
      code: code,
      englishName: code.toUpperCase(),
      nativeName: code.toUpperCase(),
    );
  }
}
