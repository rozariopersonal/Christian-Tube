import 'package:flutter/painting.dart';
import '../../core/color_utils.dart';

/// Ordered highlight palette (light → dark shades), grouped as 3 rows of 5.
///
/// This is the single source of truth for highlight colors and their contrast
/// text color. It is palette-only (no widget/Bible dependency) so it can be
/// reused by the Bible reader, book reader, articles, and any other text
/// surface.
class HighlightPalette {
  static const int count = 15;

  /// 15 colors ordered by shade depth (row-major: pastels → mid → deep).
  static const List<Color> colors = [
    // Row 1 — Pastels (light)
    Color(0xFFFFEB3B), // 0  Mustard
    Color(0xFFFFCC80), // 1  Apricot
    Color(0xFFA5D6A7), // 2  Sage
    Color(0xFF8F92E3), // 3  Periwinkle
    Color(0xFF90CAF9), // 4  Sky Blue
    // Row 2 — Mid tones
    Color(0xFFFFD54F), // 5  Marigold
    Color(0xFFFF8A65), // 6  Salmon
    Color(0xFF66BB6A), // 7  Emerald
    Color(0xFF42A5F5), // 8  Cerulean
    Color(0xFF7986CB), // 9  Indigo
    // Row 3 — Deep (dark)
    Color(0xFFF4511E), // 10 Deep Orange
    Color(0xFFAB47BC), // 11 Orchid
    Color(0xFFE53935), // 12 Crimson
    Color(0xFF26A69A), // 13 Teal
    Color(0xFF3949AB), // 14 Navy
  ];

  static Color colorFor(int index) =>
      index >= 0 && index < colors.length ? colors[index] : colors[0];

  /// Foreground color that contrasts with the highlight at [index].
  static Color onColorFor(int index) => contrastColor(colorFor(index));
}