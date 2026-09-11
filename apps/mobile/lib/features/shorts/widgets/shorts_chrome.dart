import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

/// Theme-aware chrome colors for the shorts feature.
///
/// Shorts surfaces sit over full-bleed video, so in dark mode they keep the
/// classic media scrim palette ([AppTokens.scrim] / [AppTokens.onScrim]) for
/// readability. In light mode they fall back to the normal surface palette so
/// the whole feature follows the app theme instead of forcing black.
extension ShortsChrome on BuildContext {
  /// Background used for the shorts scaffold / chrome (theme-aware).
  Color get shortsChromeBg => isDark ? tokens.scrim : tokens.surface;

  /// Secondary fill behind chips / pills (theme-aware).
  Color get shortsChromeFill => isDark ? tokens.scrim : tokens.surfaceVariant;

  /// Primary foreground for chrome over the shorts surface.
  Color get shortsChromeFg => isDark ? tokens.onScrim : tokens.onSurface;

  /// Muted foreground for chrome over the shorts surface.
  Color get shortsChromeFgMuted =>
      isDark ? tokens.onScrimMuted : tokens.onSurfaceMuted;

  /// Soft shadow colour for chrome text/edges (theme-aware).
  Color get shortsChromeShadow => isDark ? tokens.scrim : tokens.surfaceBorder;

  /// Bottom-up gradient used to mask the bottom of the player/chrome.
  List<Color> get shortsBottomGradient => isDark
      ? [
          tokens.scrim.withValues(alpha: 0.98),
          tokens.scrim.withValues(alpha: 0.87),
          tokens.scrim.withValues(alpha: 0.6),
          tokens.scrim.withValues(alpha: 0.53),
          tokens.scrim.withValues(alpha: 0.0),
        ]
      : [
          tokens.surface.withValues(alpha: 0.98),
          tokens.surface.withValues(alpha: 0.9),
          tokens.surface.withValues(alpha: 0.62),
          tokens.surface.withValues(alpha: 0.4),
          tokens.surface.withValues(alpha: 0.0),
        ];
}