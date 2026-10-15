import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BackgroundPreset {
  final String id;
  final String name;
  final List<Color> darkColors;
  final List<Color> lightColors;
  final Color defaultDarkText;
  final Color defaultLightText;
  final String? imageUrl;
  final String? blurHash;
  final bool isGradient;
  final bool isAnimatedGradient;

  const BackgroundPreset({
    required this.id,
    required this.name,
    this.darkColors = const [],
    this.lightColors = const [],
    this.defaultDarkText = const Color(0xFFFFFFFF),
    this.defaultLightText = const Color(0xFF0F172A),
    this.imageUrl,
    this.blurHash,
    List<Color>? gradientColors,
    this.isGradient = false,
    this.isAnimatedGradient = true,
  }) : _legacyGradientColors = gradientColors;

  final List<Color>? _legacyGradientColors;

  List<Color>? get gradientColors =>
      _legacyGradientColors ?? (darkColors.isNotEmpty ? darkColors : null);

  List<Color> resolveColors(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      if (darkColors.isNotEmpty) return darkColors;
      if (gradientColors != null && gradientColors!.isNotEmpty) {
        return gradientColors!;
      }
      return const [Color(0xFF000000)];
    } else {
      if (lightColors.isNotEmpty) return lightColors;
      if (gradientColors != null && gradientColors!.isNotEmpty) {
        return gradientColors!;
      }
      return const [Color(0xFFFFFFFF)];
    }
  }

  Color resolveTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? defaultDarkText : defaultLightText;
  }
}

class ScriptureFontOption {
  final String id;
  final String name;
  final String subtitle;
  final String sampleGlyph;
  final String? languageCode;

  const ScriptureFontOption({
    required this.id,
    required this.name,
    required this.subtitle,
    this.sampleGlyph = 'Aa',
    this.languageCode,
  });
}

class ScriptureColorOption {
  final String hex;
  final String name;
  final Color color;

  const ScriptureColorOption({
    required this.hex,
    required this.name,
    required this.color,
  });
}

class ScriptureThemeCatalog {
  // Available English Font Families
  static const List<ScriptureFontOption> fontOptions = [
    ScriptureFontOption(
      id: 'Playfair',
      name: 'Playfair Display',
      subtitle: 'Classic Serif',
      sampleGlyph: 'Grace',
    ),
    ScriptureFontOption(
      id: 'Cinzel',
      name: 'Cinzel',
      subtitle: 'Monumental Roman',
      sampleGlyph: 'Peace',
    ),
    ScriptureFontOption(
      id: 'Cormorant',
      name: 'Cormorant',
      subtitle: 'Regal Literature',
      sampleGlyph: 'Hope',
    ),
    ScriptureFontOption(
      id: 'Outfit',
      name: 'Outfit',
      subtitle: 'Modern Clean',
      sampleGlyph: 'Life',
    ),
    ScriptureFontOption(
      id: 'Lora',
      name: 'Lora',
      subtitle: 'Warm Editorial',
      sampleGlyph: 'Faith',
    ),
    ScriptureFontOption(
      id: 'Merriweather',
      name: 'Merriweather',
      subtitle: 'Bold Reading',
      sampleGlyph: 'Love',
    ),
    ScriptureFontOption(
      id: 'GreatVibes',
      name: 'Great Vibes',
      subtitle: 'Graceful Script',
      sampleGlyph: 'Light',
    ),
    ScriptureFontOption(
      id: 'Montserrat',
      name: 'Montserrat',
      subtitle: 'Geometric Sans',
      sampleGlyph: 'Joy',
    ),
  ];

  static List<ScriptureFontOption> getFontsForLanguage(String? languageCode) {
    switch (normalizeLanguageCode(languageCode)) {
      case 'tam':
        return const [
          ScriptureFontOption(
            id: 'MuktaMalar',
            name: 'முக்தா மலர் (Mukta Malar)',
            subtitle: 'Contemporary Tamil',
            sampleGlyph: 'அன்பு',
            languageCode: 'tam',
          ),
          ScriptureFontOption(
            id: 'NotoSerifTamil',
            name: 'நோட்டோ செரிஃப் (Noto Serif)',
            subtitle: 'Classic Literature',
            sampleGlyph: 'வேதம்',
            languageCode: 'tam',
          ),
          ScriptureFontOption(
            id: 'Catamaran',
            name: 'கட்டமரன் (Catamaran)',
            subtitle: 'Clean & Modern',
            sampleGlyph: 'சமாதானம்',
            languageCode: 'tam',
          ),
          ScriptureFontOption(
            id: 'Kavivanar',
            name: 'கவிவாணர் (Kavivanar)',
            subtitle: 'Curved Devotional',
            sampleGlyph: 'விசுவாசம்',
            languageCode: 'tam',
          ),
          ScriptureFontOption(
            id: 'ArimaMadurai',
            name: 'அரிமா மதுரை (Arima)',
            subtitle: 'Graceful Calligraphy',
            sampleGlyph: 'கிருபை',
            languageCode: 'tam',
          ),
          ScriptureFontOption(
            id: 'Coiny',
            name: 'கோய்னி (Coiny)',
            subtitle: 'Bold Rounded',
            sampleGlyph: 'ஜீவன்',
            languageCode: 'tam',
          ),
        ];

      case 'mal':
        return const [
          ScriptureFontOption(
            id: 'Gayathri',
            name: 'ഗായത്രി (Gayathri)',
            subtitle: 'Contemporary Malayalam',
            sampleGlyph: 'സ്നേഹം',
            languageCode: 'mal',
          ),
          ScriptureFontOption(
            id: 'NotoSerifMalayalam',
            name: 'നോട്ടോ സെരിഫ് (Noto Serif)',
            subtitle: 'Classic Sacred Text',
            sampleGlyph: 'സമാധാനം',
            languageCode: 'mal',
          ),
          ScriptureFontOption(
            id: 'Manjari',
            name: 'മഞ്ജരി (Manjari)',
            subtitle: 'Modern Clean',
            sampleGlyph: 'വിശ്വാസം',
            languageCode: 'mal',
          ),
          ScriptureFontOption(
            id: 'Chilanka',
            name: 'ചിലങ്ക (Chilanka)',
            subtitle: 'Handwritten Script',
            sampleGlyph: 'കൃപ',
            languageCode: 'mal',
          ),
          ScriptureFontOption(
            id: 'AnekMalayalam',
            name: 'അനേക് (Anek Malayalam)',
            subtitle: 'Bold Display',
            sampleGlyph: 'ജീവൻ',
            languageCode: 'mal',
          ),
        ];

      case 'tel':
        return const [
          ScriptureFontOption(
            id: 'Mandali',
            name: 'మండలి (Mandali)',
            subtitle: 'Clear Modern Telugu',
            sampleGlyph: 'ప్రేమ',
            languageCode: 'tel',
          ),
          ScriptureFontOption(
            id: 'NotoSerifTelugu',
            name: 'నోటో సెరిఫ్ (Noto Serif)',
            subtitle: 'Sacred Literature',
            sampleGlyph: 'శాంతి',
            languageCode: 'tel',
          ),
          ScriptureFontOption(
            id: 'Ramabhadra',
            name: 'రామభద్ర (Ramabhadra)',
            subtitle: 'Bold Royal',
            sampleGlyph: 'విశ్వాసం',
            languageCode: 'tel',
          ),
          ScriptureFontOption(
            id: 'Gidugu',
            name: 'గిడుగు (Gidugu)',
            subtitle: 'Artistic Fluid',
            sampleGlyph: 'కృప',
            languageCode: 'tel',
          ),
          ScriptureFontOption(
            id: 'Suranna',
            name: 'సూరన్న (Suranna)',
            subtitle: 'Classic Editorial',
            sampleGlyph: 'జీవము',
            languageCode: 'tel',
          ),
          ScriptureFontOption(
            id: 'AnekTelugu',
            name: 'అనేక్ (Anek Telugu)',
            subtitle: 'Modern Display',
            sampleGlyph: 'వెలుగు',
            languageCode: 'tel',
          ),
        ];

      case 'hin':
        return const [
          ScriptureFontOption(
            id: 'RozhaOne',
            name: 'रोज़ा वन (Rozha One)',
            subtitle: 'Dramatic Serif',
            sampleGlyph: 'प्रेम',
            languageCode: 'hin',
          ),
          ScriptureFontOption(
            id: 'NotoSerifDevanagari',
            name: 'नोटो सेरिफ़ (Noto Serif)',
            subtitle: 'Sacred Devanagari',
            sampleGlyph: 'शान्ति',
            languageCode: 'hin',
          ),
          ScriptureFontOption(
            id: 'YatraOne',
            name: 'यात्रा वन (Yatra One)',
            subtitle: 'Devotional Display',
            sampleGlyph: 'विश्वास',
            languageCode: 'hin',
          ),
          ScriptureFontOption(
            id: 'Kalam',
            name: 'कलम (Kalam)',
            subtitle: 'Warm Handwritten',
            sampleGlyph: 'अनुग्रह',
            languageCode: 'hin',
          ),
          ScriptureFontOption(
            id: 'Poppins',
            name: 'पॉपिन्स (Poppins)',
            subtitle: 'Clean Geometric',
            sampleGlyph: 'जीवन',
            languageCode: 'hin',
          ),
          ScriptureFontOption(
            id: 'AnekDevanagari',
            name: 'अनेक (Anek Devanagari)',
            subtitle: 'Contemporary',
            sampleGlyph: 'आशा',
            languageCode: 'hin',
          ),
        ];

      case 'kan':
        return const [
          ScriptureFontOption(
            id: 'BalooTamma2',
            name: 'ಬಾಲೂ ತಮ್ಮ ೨ (Baloo Tamma)',
            subtitle: 'Warm Rounded',
            sampleGlyph: 'ಪ್ರೀತಿ',
            languageCode: 'kan',
          ),
          ScriptureFontOption(
            id: 'NotoSerifKannada',
            name: 'ನೋಟೋ ಸೆರಿಫ್ (Noto Serif)',
            subtitle: 'Sacred Classic',
            sampleGlyph: 'ಶಾಂತಿ',
            languageCode: 'kan',
          ),
          ScriptureFontOption(
            id: 'Hubballi',
            name: 'ಹುಬ್ಬಳ್ಳಿ (Hubballi)',
            subtitle: 'Smooth Modern',
            sampleGlyph: 'ವಿಶ್ವಾಸ',
            languageCode: 'kan',
          ),
          ScriptureFontOption(
            id: 'AnekKannada',
            name: 'ಅನೇಕ (Anek Kannada)',
            subtitle: 'Bold Display',
            sampleGlyph: 'ಕೃಪೆ',
            languageCode: 'kan',
          ),
        ];

      default:
        return fontOptions;
    }
  }

  static String getDefaultFontForLanguage(String? languageCode) {
    final fonts = getFontsForLanguage(languageCode);
    if (fonts.isNotEmpty) return fonts.first.id;
    return 'Playfair';
  }

  /// Normalizes a locale/ISO language code so 2-letter (books catalog) and
  /// 3-letter (bible catalog `languageCode`) forms resolve to the same set.
  static String normalizeLanguageCode(String? languageCode) {
    switch (languageCode?.trim().toLowerCase()) {
      case 'ta':
      case 'tam':
        return 'tam';
      case 'ml':
      case 'mal':
        return 'mal';
      case 'te':
      case 'tel':
        return 'tel';
      case 'hi':
      case 'hin':
        return 'hin';
      case 'kn':
      case 'kan':
        return 'kan';
      default:
        return 'en';
    }
  }

  /// Resolves a logical [fontFamily] id to the concrete Google Fonts family
  /// name for [languageCode], mirroring [getTextStyle]:
  /// - per-language ids map to that family, unknown ids fall back to the
  ///   language's default serif;
  /// - English ids map to the Latin family, unknown ids yield `null` so the
  ///   theme font applies.
  ///
  /// Unlike [getTextStyle] this never touches Google Fonts runtime loading, so
  /// it is safe to call synchronously from pure span/paragraph builders (and
  /// in widget-free unit tests). The returned name resolves at paint time
  /// because the same family is registered app-wide via the theme text theme.
  static String? resolveFontFamily(String fontFamily, String? languageCode) {
    switch (normalizeLanguageCode(languageCode)) {
      case 'tam':
        switch (fontFamily) {
          case 'MuktaMalar':
            return 'Mukta Malar';
          case 'Catamaran':
            return 'Catamaran';
          case 'Kavivanar':
            return 'Kavivanar';
          case 'ArimaMadurai':
            return 'Arima';
          case 'Coiny':
            return 'Coiny';
          case 'NotoSerifTamil':
          default:
            return 'Noto Serif Tamil';
        }
      case 'mal':
        switch (fontFamily) {
          case 'Gayathri':
            return 'Gayathri';
          case 'Manjari':
            return 'Manjari';
          case 'Chilanka':
            return 'Chilanka';
          case 'AnekMalayalam':
            return 'Anek Malayalam';
          case 'NotoSerifMalayalam':
          default:
            return 'Noto Serif Malayalam';
        }
      case 'tel':
        switch (fontFamily) {
          case 'Mandali':
            return 'Mandali';
          case 'Ramabhadra':
            return 'Ramabhadra';
          case 'Gidugu':
            return 'Gidugu';
          case 'Suranna':
            return 'Suranna';
          case 'AnekTelugu':
            return 'Anek Telugu';
          case 'NotoSerifTelugu':
          default:
            return 'Noto Serif Telugu';
        }
      case 'hin':
        switch (fontFamily) {
          case 'RozhaOne':
            return 'Rozha One';
          case 'YatraOne':
            return 'Yatra One';
          case 'Kalam':
            return 'Kalam';
          case 'Poppins':
            return 'Poppins';
          case 'AnekDevanagari':
            return 'Anek Devanagari';
          case 'NotoSerifDevanagari':
          default:
            return 'Noto Serif Devanagari';
        }
      case 'kan':
        switch (fontFamily) {
          case 'BalooTamma2':
            return 'Baloo Tamma 2';
          case 'Hubballi':
            return 'Hubballi';
          case 'AnekKannada':
            return 'Anek Kannada';
          case 'NotoSerifKannada':
          default:
            return 'Noto Serif Kannada';
        }
      case 'en':
      default:
        switch (fontFamily) {
          case 'Cinzel':
            return 'Cinzel';
          case 'Cormorant':
            return 'Cormorant Garamond';
          case 'Outfit':
            return 'Outfit';
          case 'Lora':
            return 'Lora';
          case 'Merriweather':
            return 'Merriweather';
          case 'GreatVibes':
            return 'Great Vibes';
          case 'Montserrat':
            return 'Montserrat';
          case 'Playfair':
            return 'Playfair Display';
          default:
            return null;
        }
    }
  }

  // Curated Text Color Palette (Supports both Light and Dark backgrounds)
  static const List<ScriptureColorOption> colorPalette = [
    ScriptureColorOption(
      hex: '#FFFFFF',
      name: 'Pure White',
      color: Colors.white,
    ),
    ScriptureColorOption(
      hex: '#0F172A',
      name: 'Obsidian Ink',
      color: Color(0xFF0F172A),
    ),
    ScriptureColorOption(
      hex: '#F59E0B',
      name: 'Radiant Gold',
      color: Color(0xFFF59E0B),
    ),
    ScriptureColorOption(
      hex: '#FEF3C7',
      name: 'Warm Ivory',
      color: Color(0xFFFEF3C7),
    ),
    ScriptureColorOption(
      hex: '#1E293B',
      name: 'Deep Slate',
      color: Color(0xFF1E293B),
    ),
    ScriptureColorOption(
      hex: '#78350F',
      name: 'Warm Espresso',
      color: Color(0xFF78350F),
    ),
    ScriptureColorOption(
      hex: '#FDE68A',
      name: 'Champagne',
      color: Color(0xFFFDE68A),
    ),
    ScriptureColorOption(
      hex: '#FDA4AF',
      name: 'Rose Sunset',
      color: Color(0xFFFDA4AF),
    ),
    ScriptureColorOption(
      hex: '#7DD3FC',
      name: 'Sky Cyan',
      color: Color(0xFF7DD3FC),
    ),
    ScriptureColorOption(
      hex: '#6EE7B7',
      name: 'Mint Serenity',
      color: Color(0xFF6EE7B7),
    ),
    ScriptureColorOption(
      hex: '#DDD6FE',
      name: 'Lavender Peace',
      color: Color(0xFFDDD6FE),
    ),
  ];

  // Background Themes & Presets Catalog (Theme-Aware Solids & Sacred Gradients)
  static const List<BackgroundPreset> presets = [
    // 1. Plain Minimalist Solids (OLED & Glare-Free Paper)
    BackgroundPreset(
      id: 'true_minimalist',
      name: 'True Minimalist',
      darkColors: [Color(0xFF000000)],
      lightColors: [Color(0xFFFFFFFF)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF0F172A),
      isGradient: false,
    ),
    BackgroundPreset(
      id: 'editorial_paper',
      name: 'Editorial Paper',
      darkColors: [Color(0xFF141414)],
      lightColors: [Color(0xFFFDFBF7)],
      defaultDarkText: Color(0xFFF5F5F4),
      defaultLightText: Color(0xFF1C1917),
      isGradient: false,
    ),
    BackgroundPreset(
      id: 'obsidian_slate',
      name: 'Obsidian Slate',
      darkColors: [Color(0xFF0F172A)],
      lightColors: [Color(0xFFF1F5F9)],
      defaultDarkText: Color(0xFFF8FAFC),
      defaultLightText: Color(0xFF0F172A),
      isGradient: false,
    ),
    BackgroundPreset(
      id: 'sanctuary_warmth',
      name: 'Sanctuary Warmth',
      darkColors: [Color(0xFF1C1917)],
      lightColors: [Color(0xFFFFFBEB)],
      defaultDarkText: Color(0xFFFEF3C7),
      defaultLightText: Color(0xFF292524),
      isGradient: false,
    ),

    // 2. Sacred Gradients (Living Ambient Motions)
    BackgroundPreset(
      id: 'gradient_living_waters',
      name: 'Living Waters',
      isGradient: true,
      darkColors: [Color(0xFF082F49), Color(0xFF0C4A6E), Color(0xFF0369A1)],
      lightColors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF0C4A6E),
    ),
    BackgroundPreset(
      id: 'gradient_living_hope',
      name: 'Living Hope',
      isGradient: true,
      darkColors: [Color(0xFF052E16), Color(0xFF064E3B), Color(0xFF047857)],
      lightColors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF064E3B),
    ),
    BackgroundPreset(
      id: 'gradient_celestial_dawn',
      name: 'Celestial Dawn',
      isGradient: true,
      darkColors: [Color(0xFF3B0764), Color(0xFF581C87), Color(0xFF701A75)],
      lightColors: [Color(0xFFFDF4FF), Color(0xFFFAE8FF), Color(0xFFE9D5FF)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF3B0764),
    ),
    BackgroundPreset(
      id: 'gradient_divine_amber',
      name: 'Divine Amber',
      isGradient: true,
      darkColors: [Color(0xFF451A03), Color(0xFF78350F), Color(0xFF9A3412)],
      lightColors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7), Color(0xFFFDE68A)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF451A03),
    ),
    BackgroundPreset(
      id: 'gradient_twilight_peace',
      name: 'Twilight Peace',
      isGradient: true,
      darkColors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF1E293B)],
      lightColors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF1E1B4B),
    ),
    BackgroundPreset(
      id: 'gradient_royal_midnight',
      name: 'Royal Midnight',
      isGradient: true,
      darkColors: [Color(0xFF090D16), Color(0xFF0F172A), Color(0xFF1E1B4B)],
      lightColors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
      defaultDarkText: Color(0xFFFFFFFF),
      defaultLightText: Color(0xFF0F172A),
    ),
  ];

  static final Map<String, BackgroundPreset> _legacyAliases = {
    'mountain_dawn': presets.firstWhere((p) => p.id == 'gradient_celestial_dawn'),
    'starry_night': presets.firstWhere((p) => p.id == 'gradient_royal_midnight'),
    'calm_ocean': presets.firstWhere((p) => p.id == 'gradient_living_waters'),
    'misty_forest': presets.firstWhere((p) => p.id == 'gradient_living_hope'),
    'golden_fields': presets.firstWhere((p) => p.id == 'gradient_divine_amber'),
    'desert_dunes': presets.firstWhere((p) => p.id == 'sanctuary_warmth'),
    'autumn_leaves': presets.firstWhere((p) => p.id == 'gradient_divine_amber'),
    'night_sky': presets.firstWhere((p) => p.id == 'gradient_twilight_peace'),
    'gradient_radiant_gold': presets.firstWhere((p) => p.id == 'gradient_divine_amber'),
    'gradient_celestial_rose': presets.firstWhere((p) => p.id == 'gradient_celestial_dawn'),
    'gradient_emerald_sanctuary': presets.firstWhere((p) => p.id == 'gradient_living_hope'),
    'gradient_majestic_purple': presets.firstWhere((p) => p.id == 'gradient_celestial_dawn'),
    'gradient_deep_ocean': presets.firstWhere((p) => p.id == 'gradient_living_waters'),
  };

  static BackgroundPreset getPreset(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return _legacyAliases[id] ?? presets.first;
  }

  static Color parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      } else if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return Colors.white;
  }

  static TextStyle getTextStyle({
    required String fontFamily,
    required String languageCode,
    double baseSize = 22.0,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    Color color = Colors.white,
  }) {
    final lang = normalizeLanguageCode(languageCode);

    // 1. Tamil Fonts
    if (lang == 'tam') {
      switch (fontFamily) {
        case 'MuktaMalar':
          return GoogleFonts.muktaMalar(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Catamaran':
          return GoogleFonts.catamaran(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Kavivanar':
          return GoogleFonts.kavivanar(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'ArimaMadurai':
          return GoogleFonts.arima(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Coiny':
          return GoogleFonts.coiny(
            fontSize: baseSize - 2,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'NotoSerifTamil':
        default:
          return GoogleFonts.notoSerifTamil(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
      }
    }

    // 2. Malayalam Fonts
    if (lang == 'mal') {
      switch (fontFamily) {
        case 'Gayathri':
          return GoogleFonts.gayathri(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Manjari':
          return GoogleFonts.manjari(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Chilanka':
          return GoogleFonts.chilanka(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'AnekMalayalam':
          return GoogleFonts.anekMalayalam(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'NotoSerifMalayalam':
        default:
          return GoogleFonts.notoSerifMalayalam(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
      }
    }

    // 3. Telugu Fonts
    if (lang == 'tel') {
      switch (fontFamily) {
        case 'Mandali':
          return GoogleFonts.mandali(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Ramabhadra':
          return GoogleFonts.ramabhadra(
            fontSize: baseSize - 2,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Gidugu':
          return GoogleFonts.gidugu(
            fontSize: baseSize + 2,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Suranna':
          return GoogleFonts.suranna(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'AnekTelugu':
          return GoogleFonts.anekTelugu(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'NotoSerifTelugu':
        default:
          return GoogleFonts.notoSerifTelugu(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
      }
    }

    // 4. Hindi (Devanagari) Fonts
    if (lang == 'hin') {
      switch (fontFamily) {
        case 'RozhaOne':
          return GoogleFonts.rozhaOne(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'YatraOne':
          return GoogleFonts.yatraOne(
            fontSize: baseSize - 2,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Kalam':
          return GoogleFonts.kalam(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Poppins':
          return GoogleFonts.poppins(
            fontSize: baseSize - 1,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'AnekDevanagari':
          return GoogleFonts.anekDevanagari(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'NotoSerifDevanagari':
        default:
          return GoogleFonts.notoSerifDevanagari(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
      }
    }

    // 5. Kannada Fonts
    if (lang == 'kan') {
      switch (fontFamily) {
        case 'BalooTamma2':
          return GoogleFonts.balooTamma2(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'Hubballi':
          return GoogleFonts.hubballi(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'AnekKannada':
          return GoogleFonts.anekKannada(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
        case 'NotoSerifKannada':
        default:
          return GoogleFonts.notoSerifKannada(
            fontSize: baseSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: 1.45,
          );
      }
    }

    // 6. English / Latin Fonts
    switch (fontFamily) {
      case 'Cinzel':
        return GoogleFonts.cinzel(
          fontSize: baseSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          letterSpacing: 0.5,
          height: 1.4,
        );
      case 'Cormorant':
        return GoogleFonts.cormorantGaramond(
          fontSize: baseSize + 2,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.35,
        );
      case 'Outfit':
        return GoogleFonts.outfit(
          fontSize: baseSize - 1,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.35,
        );
      case 'Lora':
        return GoogleFonts.lora(
          fontSize: baseSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.4,
        );
      case 'Merriweather':
        return GoogleFonts.merriweather(
          fontSize: baseSize - 1,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.45,
        );
      case 'GreatVibes':
        return GoogleFonts.greatVibes(
          fontSize: baseSize + 8,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.25,
        );
      case 'Montserrat':
        return GoogleFonts.montserrat(
          fontSize: baseSize - 1,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.4,
        );
      case 'Playfair':
      default:
        return GoogleFonts.playfairDisplay(
          fontSize: baseSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: 1.4,
        );
    }
  }
}
