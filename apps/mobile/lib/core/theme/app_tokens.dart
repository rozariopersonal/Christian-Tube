import 'package:flutter/material.dart';

/// Design tokens for the app.
///
/// All UI colors must be read through [AppTokens] (via `context.tokens`) or
/// `Theme.of(context).colorScheme`. Never hardcode raw `Colors.*` or hex
/// values in `lib/` — doing so breaks dark/light/AMOLED and accent theming.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Scaffold / window background.
  final Color background;

  /// Cards and elevated surfaces.
  final Color surface;

  /// Subtle, muted fills (replaces `grey.shade100` / `grey.shade900`).
  final Color surfaceVariant;

  /// Slightly raised surface (replaces `grey.shade50` / near-`surface` fills).
  final Color surfaceElevated;

  /// Hairline borders between/around surfaces.
  final Color surfaceBorder;

  /// Primary text on surfaces.
  final Color onSurface;

  /// Secondary / muted text (replaces `grey.shade500`).
  final Color onSurfaceMuted;

  /// Disabled text.
  final Color onSurfaceDisabled;

  /// App accent color (secondary brand color).
  final Color accent;

  /// Dark scrim used over media / immersive surfaces.
  final Color scrim;

  /// Whether this token set represents a dark theme.
  final bool isDark;

  const AppTokens({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.surfaceBorder,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onSurfaceDisabled,
    required this.accent,
    required this.scrim,
    required this.isDark,
  });

  static const AppTokens light = AppTokens(
    background: Color(0xFFF8FAFC),
    surface: Colors.white,
    surfaceVariant: Color(0xFFF1F5F9),
    surfaceElevated: Color(0xFFF8FAFC),
    surfaceBorder: Colors.black12,
    onSurface: Colors.black87,
    onSurfaceMuted: Colors.black54,
    onSurfaceDisabled: Colors.black38,
    accent: Color(0xFFF59E0B),
    scrim: Colors.black,
    isDark: false,
  );

  static const AppTokens dark = AppTokens(
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    surfaceVariant: Color(0xFF1E293B),
    surfaceElevated: Color(0xFF283548),
    surfaceBorder: Colors.white12,
    onSurface: Colors.white,
    onSurfaceMuted: Colors.white60,
    onSurfaceDisabled: Colors.white38,
    accent: Color(0xFFF59E0B),
    scrim: Colors.black,
    isDark: true,
  );

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceElevated,
    Color? surfaceBorder,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? onSurfaceDisabled,
    Color? accent,
    Color? scrim,
    bool? isDark,
  }) {
    return AppTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      onSurfaceDisabled: onSurfaceDisabled ?? this.onSurfaceDisabled,
      accent: accent ?? this.accent,
      scrim: scrim ?? this.scrim,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceBorder: Color.lerp(surfaceBorder, other.surfaceBorder, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      onSurfaceDisabled: Color.lerp(onSurfaceDisabled, other.onSurfaceDisabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      isDark: other.isDark,
    );
  }
}

/// Convenient theme accessors.
extension AppTokensX on BuildContext {
  AppTokens get tokens {
    final t = Theme.of(this).extension<AppTokens>();
    if (t != null) return t;
    return Theme.of(this).brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
  }

  bool get isDark => tokens.isDark;

  /// Primary brand color (accent seed) from the active scheme.
  Color get primary => Theme.of(this).colorScheme.primary;

  /// Secondary brand accent color.
  Color get accent => tokens.accent;
}
