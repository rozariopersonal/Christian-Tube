import 'package:flutter/widgets.dart';

/// Material 3 WindowSizeClass-derived size classes.
///
/// This is the single source of truth for responsive behavior. Widgets must
/// resolve the size class through [ScreenClass.of] and **must not** inline
/// breakpoint comparisons (`MediaQuery.width > 900 ? ...`).
enum ScreenClass {
  /// Width `< 600` — phones portrait.
  compact,

  /// Width `600 – 839` — small tablets, large phones landscape.
  medium,

  /// Width `>= 840` — tablets, web, desktop windows.
  expanded;

  bool get isCompact => this == ScreenClass.compact;

  bool get isMediumOrExpanded => !isCompact;

  static ScreenClass of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ofWidth(width);
  }

  /// Pure width mapping so tests can exercise it without a widget tree.
  static ScreenClass ofWidth(double width) {
    if (width < 600) return ScreenClass.compact;
    if (width < 840) return ScreenClass.medium;
    return ScreenClass.expanded;
  }
}

/// Preferred grid column counts for content whose tiles adapt to the screen
/// class (e.g. the video feed). Content with a strict min tile width should
/// use [minTileExtent] with `SliverGridDelegateWithMaxCrossAxisExtent` instead.
int gridColumnsFor(BuildContext context, {int compact = 1, int medium = 2, int expanded = 3}) {
  switch (ScreenClass.of(context)) {
    case ScreenClass.compact:
      return compact;
    case ScreenClass.medium:
      return medium;
    case ScreenClass.expanded:
      return expanded;
  }
}

/// Recommended minimum tile widths (dp) for shared grid content.
class GridExtents {
  GridExtents._();

  /// Shorts / micro-feed tiles.
  static const double shorts = 150;

  /// Video feed grid cards on `medium`+ screens.
  static const double feed = 320;

  /// Bible manager catalog tiles.
  static const double bibleManager = 340;
}

/// Navigation shell mode for the current window.
enum AppNavMode {
  /// Bottom `NavigationBar` — `compact` portrait.
  bottomBar,

  /// Left `NavigationRail` — `medium`/`expanded`.
  rail,

  /// No shell navigation (fullscreen media, overlay surfaces).
  hidden,
}

/// Pure decision logic for which shell navigation to show.
///
/// - `compact` portrait keeps the bottom bar; `compact` landscape hides it
///   (matching the legacy fullscreen-video behavior on phones).
/// - `medium`/`expanded` always use a rail, except during fullscreen media
///   (shorts playing, or the landscape watch player on non-web platforms).
/// - Explicit hides always suppress navigation.
AppNavMode resolveNavMode({
  required double width,
  required bool isLandscape,
  required bool isShortPlaying,
  required bool isExplicitlyHidden,
  required bool isWatchRoute,
  required bool isWeb,
}) {
  if (isExplicitlyHidden || isShortPlaying) return AppNavMode.hidden;
  final isCompact = width < 600;
  if (isCompact) {
    return isLandscape ? AppNavMode.hidden : AppNavMode.bottomBar;
  }
  final fullscreenMedia = !isWeb && isLandscape && isWatchRoute;
  return fullscreenMedia ? AppNavMode.hidden : AppNavMode.rail;
}