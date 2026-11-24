/// Unified cross-platform font catalog models matching `releases/fonts/catalog.json`.
class FontLanguageMeta {
  final String code;
  final List<String> aliases;
  final String label;
  final String nativeLabel;
  final String sampleText;

  const FontLanguageMeta({
    required this.code,
    this.aliases = const [],
    required this.label,
    required this.nativeLabel,
    required this.sampleText,
  });

  factory FontLanguageMeta.fromJson(Map<String, dynamic> json) {
    return FontLanguageMeta(
      code: (json['code'] as String? ?? 'en').trim().toLowerCase(),
      aliases: (json['aliases'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().trim().toLowerCase())
          .toList(),
      label: json['label'] as String? ?? 'English',
      nativeLabel: json['nativeLabel'] as String? ?? 'English',
      sampleText: json['sampleText'] as String? ?? 'In the beginning was the Word',
    );
  }
}

class FontCatalogEntry {
  final String id;
  final List<String> legacyIds;
  final String family;
  final String label;
  final String shortLabel;
  final String subtitle;
  final String language;
  final String category;
  final String license;
  final String source;
  final String sampleGlyph;
  final String sampleText;
  final Map<String, String> files;

  const FontCatalogEntry({
    required this.id,
    this.legacyIds = const [],
    required this.family,
    required this.label,
    required this.shortLabel,
    required this.subtitle,
    required this.language,
    required this.category,
    this.license = 'OFL-1.1',
    this.source = 'ondemand',
    this.sampleGlyph = 'Aa',
    this.sampleText = 'In the beginning was the Word',
    this.files = const {},
  });

  factory FontCatalogEntry.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as Map<String, dynamic>? ?? const {};
    return FontCatalogEntry(
      id: (json['id'] as String? ?? '').trim(),
      legacyIds: (json['legacyIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().trim())
          .toList(),
      family: (json['family'] as String? ?? '').trim(),
      label: json['label'] as String? ?? '',
      shortLabel: json['shortLabel'] as String? ?? json['label'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      language: (json['language'] as String? ?? 'en').trim().toLowerCase(),
      category: (json['category'] as String? ?? 'sans').trim().toLowerCase(),
      license: json['license'] as String? ?? 'OFL-1.1',
      source: json['source'] as String? ?? 'ondemand',
      sampleGlyph: json['sampleGlyph'] as String? ?? 'Aa',
      sampleText: json['sampleText'] as String? ?? 'In the beginning was the Word',
      files: rawFiles.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

class FontCatalog {
  final int version;
  final List<FontLanguageMeta> languages;
  final List<FontCatalogEntry> fonts;

  const FontCatalog({
    this.version = 1,
    this.languages = const [],
    this.fonts = const [],
  });

  factory FontCatalog.fromJson(Map<String, dynamic> json) {
    final langs = (json['languages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FontLanguageMeta.fromJson)
        .toList();
    final entries = (json['fonts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FontCatalogEntry.fromJson)
        .where((e) => e.id.isNotEmpty && e.family.isNotEmpty)
        .toList();
    return FontCatalog(
      version: json['version'] as int? ?? 1,
      languages: langs,
      fonts: entries,
    );
  }

  bool get isEmpty => fonts.isEmpty;

  String normalizeLanguage(String? code) {
    final lower = code?.trim().toLowerCase() ?? 'en';
    for (final lang in languages) {
      if (lang.code == lower || lang.aliases.contains(lower)) {
        return lang.code;
      }
    }
    return lower;
  }

  FontCatalogEntry? findByIdOrLegacy(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    for (final f in fonts) {
      if (f.id == trimmed ||
          f.family == trimmed ||
          f.legacyIds.contains(trimmed)) {
        return f;
      }
    }
    return null;
  }

  FontCatalogEntry? findByFamily(String family) {
    final trimmed = family.trim();
    for (final f in fonts) {
      if (f.family == trimmed) return f;
    }
    return null;
  }

  List<FontCatalogEntry> fontsForLanguage(String? languageCode) {
    final norm = normalizeLanguage(languageCode);
    return fonts.where((f) => f.language == norm).toList();
  }
}
