import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BackgroundPreset {
  final String id;
  final String name;
  final String? imageUrl;
  final String? blurHash;
  final List<Color>? gradientColors;
  final bool isGradient;

  const BackgroundPreset({
    required this.id,
    required this.name,
    this.imageUrl,
    this.blurHash,
    this.gradientColors,
    this.isGradient = false,
  });
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
    switch (languageCode) {
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

  // Curated Text Color Palette
  static const List<ScriptureColorOption> colorPalette = [
    ScriptureColorOption(
      hex: '#FFFFFF',
      name: 'Pure White',
      color: Colors.white,
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

  // Background Wallpapers & Themes Catalog
  static const List<BackgroundPreset> presets = [
    // 1. High-Res Curated Photos
    BackgroundPreset(
      id: 'mountain_dawn',
      name: 'Mountain Dawn',
      imageUrl:
          'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L6PZfSi_.AyE_3t7t7R**0o#DgR4',
    ),
    BackgroundPreset(
      id: 'starry_night',
      name: 'Starry Cosmos',
      imageUrl:
          'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L01n9aWB00of_3WBofWB00of_3WB',
    ),
    BackgroundPreset(
      id: 'calm_ocean',
      name: 'Calm Ocean',
      imageUrl:
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'LEHV6nWB2yk8pyo0adRjQ-kCM|j[',
    ),
    BackgroundPreset(
      id: 'misty_forest',
      name: 'Misty Forest',
      imageUrl:
          'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L5B:d;%M00IU00t7xut700%M?bIU',
    ),
    BackgroundPreset(
      id: 'golden_fields',
      name: 'Golden Fields',
      imageUrl:
          'https://images.unsplash.com/photo-1470240731273-7821a6eeb6bd?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L9F5W-~q00%M00of%Mof00%M_3of',
    ),
    BackgroundPreset(
      id: 'desert_dunes',
      name: 'Desert Twilight',
      imageUrl:
          'https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L6I5+q%M~qof_3WB%Mof00%M_3of',
    ),
    BackgroundPreset(
      id: 'autumn_leaves',
      name: 'Autumn Glory',
      imageUrl:
          'https://images.unsplash.com/photo-1507371341162-763b5e419408?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L8E_#J_300of~qof%Mof00%M_3of',
    ),
    BackgroundPreset(
      id: 'night_sky',
      name: 'Aurora Borealis',
      imageUrl:
          'https://images.unsplash.com/photo-1531366936337-7c912a4589a7?auto=format&fit=crop&w=1080&q=80',
      blurHash: 'L01#o^of00of~qofofof00of_3of',
    ),

    // 2. Artistic Sacred Gradients
    BackgroundPreset(
      id: 'gradient_royal_midnight',
      name: 'Royal Midnight',
      isGradient: true,
      gradientColors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
    ),
    BackgroundPreset(
      id: 'gradient_radiant_gold',
      name: 'Divine Amber',
      isGradient: true,
      gradientColors: [Color(0xFF78350F), Color(0xFFB45309), Color(0xFFD97706)],
    ),
    BackgroundPreset(
      id: 'gradient_celestial_rose',
      name: 'Celestial Dawn',
      isGradient: true,
      gradientColors: [Color(0xFF4C0519), Color(0xFF881337), Color(0xFFBE123C)],
    ),
    BackgroundPreset(
      id: 'gradient_emerald_sanctuary',
      name: 'Living Hope',
      isGradient: true,
      gradientColors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF047857)],
    ),
    BackgroundPreset(
      id: 'gradient_majestic_purple',
      name: 'Majestic Glory',
      isGradient: true,
      gradientColors: [Color(0xFF3B0764), Color(0xFF581C87), Color(0xFF6B21A8)],
    ),
    BackgroundPreset(
      id: 'gradient_deep_ocean',
      name: 'Living Waters',
      isGradient: true,
      gradientColors: [Color(0xFF0C4A6E), Color(0xFF0369A1), Color(0xFF0284C7)],
    ),
  ];

  static BackgroundPreset getPreset(String id) {
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () => presets.first,
    );
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
    // 1. Tamil Fonts
    if (languageCode == 'tam') {
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
    if (languageCode == 'mal') {
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
    if (languageCode == 'tel') {
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
    if (languageCode == 'hin') {
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
    if (languageCode == 'kan') {
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
