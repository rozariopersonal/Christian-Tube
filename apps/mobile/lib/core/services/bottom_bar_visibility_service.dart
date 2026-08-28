import 'dart:async';
import 'package:flutter/material.dart';

/// Centralized service to manage bottom navigation tab bar visibility across the entire app.
class BottomBarVisibilityService extends ChangeNotifier {
  static final BottomBarVisibilityService instance = BottomBarVisibilityService._();
  BottomBarVisibilityService._();

  // ── Shorts grid-reset signal ──────────────────────────────────────────────
  final StreamController<void> _shortsResetController =
      StreamController<void>.broadcast();

  /// Subscribe to this stream to be notified when the Shorts tab is re-tapped
  /// while it is already active (i.e. the user wants to return to the grid).
  Stream<void> get onShortsResetRequested => _shortsResetController.stream;

  /// Fire the reset signal. Called by the bottom nav when the Shorts tab is
  /// tapped while Shorts is already the current branch.
  void requestShortsReset() {
    if (!_shortsResetController.isClosed) {
      _shortsResetController.add(null);
    }
  }

  // ── Words refresh signal ──────────────────────────────────────────────
  final StreamController<void> _wordsResetController =
      StreamController<void>.broadcast();

  Stream<void> get onWordsResetRequested => _wordsResetController.stream;

  void requestWordsReset() {
    if (!_wordsResetController.isClosed) {
      _wordsResetController.add(null);
    }
  }

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

    // 2. Hide when a short video is actively playing
    if (_isShortPlaying) return false;

    // 3. Hide if explicitly requested (e.g. modals, croppers, overlays)
    if (_isExplicitlyHidden) return false;

    // 4. Default: Show bottom tabs in all screens and portrait modes (including Shorts browsing grid)
    return true;
  }
}
