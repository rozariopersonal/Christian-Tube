import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../layout/adaptivity.dart';

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

  /// Whether the bottom tab bar should be visible in the current context.
  ///
  /// Delegates to [resolveNavMode] so the shell has exactly one navigation
  /// policy: the bottom bar is only shown when the resolved mode is `bottomBar`
  /// (compact portrait). Compact landscape uses a rail instead; fullscreen
  /// media suppresses all navigation.
  bool shouldShow({
    required BuildContext context,
    required String currentPath,
    int? selectedIndex,
  }) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final mode = resolveNavMode(
      width: size.width,
      isLandscape: isLandscape,
      isShortPlaying: _isShortPlaying,
      isExplicitlyHidden: _isExplicitlyHidden,
      isWatchRoute: currentPath.startsWith('/watch'),
      isWeb: kIsWeb,
    );
    return mode == AppNavMode.bottomBar;
  }
}
