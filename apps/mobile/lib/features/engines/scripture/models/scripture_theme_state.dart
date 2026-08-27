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

  const ScriptureFontOption({
    required this.id,
    required this.name,
    required this.subtitle,
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
  // Available Font Families
  static const List<ScriptureFontOption> fontOptions = [
    ScriptureFontOption(
      id: 'Playfair',
      name: 'Playfair Display',
      subtitle: 'Classic Serif',
    ),
    ScriptureFontOption(
      id: 'Cinzel',
      name: 'Cinzel',
      subtitle: 'Monumental Roman',
    ),
    ScriptureFontOption(
      id: 'Cormorant',
      name: 'Cormorant',
      subtitle: 'Regal Literature',
    ),
    ScriptureFontOption(
      id: 'Outfit',
      name: 'Outfit',
      subtitle: 'Modern Clean',
    ),
    ScriptureFontOption(
      id: 'Lora',
      name: 'Lora',
      subtitle: 'Warm Editorial',
    ),
    ScriptureFontOption(
      id: 'Merriweather',
      name: 'Merriweather',
      subtitle: 'Bold Reading',
    ),
    ScriptureFontOption(
      id: 'GreatVibes',
      name: 'Great Vibes',
      subtitle: 'Graceful Script',
    ),
  ];

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
      blurHash: 'L9Gb6F_300IU00of%Mof00IU~qof',
    ),

    // 2. Procedural Offline Gradients (100% Offline, Zero Bandwidth)
    BackgroundPreset(
      id: 'midnight_obsidian',
      name: 'Midnight Obsidian',
      isGradient: true,
      gradientColors: [Color(0xFF0F172A), Color(0xFF020617), Color(0xFF000000)],
    ),
    BackgroundPreset(
      id: 'royal_indigo',
      name: 'Royal Indigo',
      isGradient: true,
      gradientColors: [Color(0xFF1E1B4B), Color(0xFF0F172A), Color(0xFF020617)],
    ),
    BackgroundPreset(
      id: 'emerald_peace',
      name: 'Emerald Serenity',
      isGradient: true,
      gradientColors: [Color(0xFF064E3B), Color(0xFF022C22), Color(0xFF011410)],
    ),
    BackgroundPreset(
      id: 'amber_dusk',
      name: 'Amber Glow',
      isGradient: true,
      gradientColors: [Color(0xFF451A03), Color(0xFF2E1065), Color(0xFF0F172A)],
    ),
    BackgroundPreset(
      id: 'pure_dark',
      name: 'Pure OLED Dark',
      isGradient: true,
      gradientColors: [Color(0xFF0A0A0A), Color(0xFF000000)],
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
    // Language-aware font selection
    if (languageCode == 'tam') {
      return GoogleFonts.notoSerifTamil(
        fontSize: baseSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        height: 1.45,
      );
    } else if (languageCode == 'mal') {
      return GoogleFonts.notoSerifMalayalam(
        fontSize: baseSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        height: 1.45,
      );
    } else if (languageCode == 'hin') {
      return GoogleFonts.notoSerifDevanagari(
        fontSize: baseSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        height: 1.45,
      );
    }

    // English font families
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
