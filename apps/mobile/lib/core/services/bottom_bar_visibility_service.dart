import 'package:flutter/material.dart';

/// Centralized service to manage bottom navigation tab bar visibility across the entire app.
class BottomBarVisibilityService extends ChangeNotifier {
  static final BottomBarVisibilityService instance = BottomBarVisibilityService._();
  BottomBarVisibilityService._();

  bool _isShortPlaying = false;
  bool _isExplicitlyHidden = false;

  bool get isShortPlaying => _isShortPlaying;
  bool get isExplicitlyHidden => _isExplicitlyHidden;

  /// Notify the service whether a short video is currently active/playing.
  void setShortPlaying(bool playing) {
    if (_isShortPlaying != playing) {
      _isShortPlaying = playing;
      notifyListeners();
    }
  }

  /// Explicitly hide or show the bottom bar (for modal dialogs, croppers, or overlays).
  void setExplicitlyHidden(bool hidden) {
    if (_isExplicitlyHidden != hidden) {
      _isExplicitlyHidden = hidden;
      notifyListeners();
    }
  }

  /// Calculates whether the bottom navigation tabs should be visible given the current context and route.
  bool shouldShow({
    required BuildContext context,
    required String currentPath,
    int? selectedIndex,
  }) {
    // 1. Hide when device/screen is in Landscape (e.g. Fullscreen Video Player)
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) return false;

    // 2. Hide when on the Shorts route (/shorts)
    if (currentPath.startsWith('/shorts') || selectedIndex == 1) return false;

    // 3. Hide when a short is actively playing
    if (_isShortPlaying) return false;

    // 4. Hide if explicitly requested
    if (_isExplicitlyHidden) return false;

    // 5. Default: Show bottom tabs in all other screens and portrait modes
    return true;
  }
}
