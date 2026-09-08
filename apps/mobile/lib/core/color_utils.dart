import 'package:flutter/painting.dart';

/// Returns a foreground color (white or dark) that contrasts well with [bg].
Color contrastColor(Color bg) {
  return bg.computeLuminance() > 0.45
      ? const Color(0xDE000000) // black87
      : const Color(0xFFFFFFFF);
}
