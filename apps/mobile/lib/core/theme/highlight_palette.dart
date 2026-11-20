import 'package:flutter/painting.dart';

import '../../core/color_utils.dart';
import 'theme_service.dart';

/// Ordered highlight palette derived from [AppColorTheme] accents:
/// 4 shade rows (Light, Soft, Base, Deep) × 7 accent columns = 28 colors.
///
/// This is the single source of truth for highlight colors and their contrast
/// text color across the Bible, Book, and Article readers.
class HighlightPalette {
  static const int shadesPerAccent = 4;
  static const int accentCount = 7;
  static const int count = shadesPerAccent * accentCount; // 28

  static const List<String> _shadeLabels = ['Light', 'Soft', '', 'Deep'];

  /// Default top-3 swatches until usage data accumulates:
  /// Warm Amber Light (4), Emerald Green Light (2), Sapphire Blue Light (0).
  static const List<int> defaultTopIndices = [4, 2, 0];

  static final List<Color> colors = _buildColors();
  static final List<String> names = _buildNames();

  static List<Color> _buildColors() {
    const accents = AppColorTheme.values;
    final out = <Color>[];
    // Row 0: Light (68% white), Row 1: Soft (36% white),
    // Row 2: Base (exact accent), Row 3: Deep (34% black).
    for (var shade = 0; shade < shadesPerAccent; shade++) {
      for (final theme in accents) {
        out.add(_shadeFor(theme.color, shade));
      }
    }
    return List.unmodifiable(out);
  }

  static List<String> _buildNames() {
    const accents = AppColorTheme.values;
    final out = <String>[];
    for (var shade = 0; shade < shadesPerAccent; shade++) {
      final suffix = _shadeLabels[shade];
      for (final theme in accents) {
        out.add(suffix.isEmpty ? theme.name : '${theme.name} $suffix');
      }
    }
    return List.unmodifiable(out);
  }

  static Color _shadeFor(Color base, int shade) {
    final r = (base.r * 255.0).round();
    final g = (base.g * 255.0).round();
    final b = (base.b * 255.0).round();
    switch (shade) {
      case 0:
        return _mix(r, g, b, 255, 255, 255, 0.68);
      case 1:
        return _mix(r, g, b, 255, 255, 255, 0.36);
      case 3:
        return _mix(r, g, b, 0, 0, 0, 0.34);
      case 2:
      default:
        return base;
    }
  }

  static Color _mix(
    int r1,
    int g1,
    int b1,
    int r2,
    int g2,
    int b2,
    double t,
  ) {
    final r = (r1 * (1 - t) + r2 * t).round().clamp(0, 255);
    final g = (g1 * (1 - t) + g2 * t).round().clamp(0, 255);
    final b = (b1 * (1 - t) + b2 * t).round().clamp(0, 255);
    return Color.fromARGB(0xFF, r, g, b);
  }

  static Color colorFor(int index) =>
      index >= 0 && index < colors.length ? colors[index] : colors[defaultTopIndices.first];

  /// Name of the highlight color at [index].
  static String nameFor(int index) =>
      index >= 0 && index < names.length ? names[index] : 'Color $index';

  /// Foreground color that contrasts with the highlight at [index].
  static Color onColorFor(int index) => contrastColor(colorFor(index));

  /// Maps a legacy 15-color Bible palette index (0..14) to the closest
  /// accent-derived index in 0..27.
  static const List<int> _legacyBibleToNew = [
    4,  // 0  Mustard     -> Warm Amber Light
    11, // 1  Apricot     -> Warm Amber Soft
    2,  // 2  Sage        -> Emerald Green Light
    10, // 3  Periwinkle  -> Violet Purple Soft
    0,  // 4  Sky Blue    -> Sapphire Blue Light
    18, // 5  Marigold    -> Warm Amber
    8,  // 6  Salmon      -> Royal Crimson Soft
    9,  // 7  Emerald     -> Emerald Green Soft
    7,  // 8  Cerulean    -> Sapphire Blue Soft
    3,  // 9  Indigo      -> Violet Purple Light
    15, // 10 Deep Orange -> Royal Crimson
    12, // 11 Orchid      -> Rose Pink Soft
    22, // 12 Crimson     -> Royal Crimson Deep
    20, // 13 Teal        -> Cyan Teal
    21, // 14 Navy        -> Sapphire Blue Deep
  ];

  static int migrateLegacyIndex(int oldIndex) {
    if (oldIndex >= 0 && oldIndex < _legacyBibleToNew.length) {
      return _legacyBibleToNew[oldIndex];
    }
    if (oldIndex >= 0 && oldIndex < count) return oldIndex;
    return defaultTopIndices.first;
  }

  /// Maps a legacy 4-color Book highlight index (0=Yellow, 1=Green, 2=Blue,
  /// 3=Pink) to the new palette.
  static int migrateLegacyBookIndex(int oldIndex) {
    switch (oldIndex) {
      case 0:
        return 4; // Warm Amber Light
      case 1:
        return 2; // Emerald Green Light
      case 2:
        return 0; // Sapphire Blue Light
      case 3:
        return 5; // Rose Pink Light
      default:
        return oldIndex >= 0 && oldIndex < count
            ? oldIndex
            : defaultTopIndices.first;
    }
  }
}
