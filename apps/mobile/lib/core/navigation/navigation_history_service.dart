import 'package:flutter/foundation.dart';

/// Tracks user navigation history across root tabs and in-shell routes.
///
/// Enables system back buttons and gestures to unwind tab switching (e.g.
/// Feed -> Bible -> Audio unwinding back to Bible, then Feed) and provides a
/// 2-second double-tap exit window when on the home feed.
class NavigationHistoryService {
  NavigationHistoryService._();
  static final NavigationHistoryService instance = NavigationHistoryService._();

  final List<String> _tabHistory = ['/feed'];
  DateTime? _lastBackPressTime;

  /// Current history depth for tests and inspection.
  int get depth => _tabHistory.length;

  /// The active root tab path.
  String get currentTab => _tabHistory.isNotEmpty ? _tabHistory.last : '/feed';

  /// Records a tab transition. Ignores consecutive duplicate paths.
  void recordTab(String path) {
    if (path.isEmpty) return;
    if (_tabHistory.isNotEmpty && _tabHistory.last == path) return;
    _tabHistory.add(path);
  }

  /// Pops the current tab and returns the previous tab path to navigate to.
  /// Returns `null` if there is no previous tab history (i.e. already at base).
  String? popPreviousTab() {
    if (_tabHistory.length > 1) {
      _tabHistory.removeLast();
      return _tabHistory.last;
    }
    return null;
  }

  /// Checks if the back press constitutes a double-tap within 2 seconds.
  /// If true, the caller should exit the app. If false, records timestamp
  /// and caller should display "Press back again to exit".
  bool shouldExitOnDoubleBack({Duration timeout = const Duration(seconds: 2)}) {
    final now = DateTime.now();
    if (_lastBackPressTime != null &&
        now.difference(_lastBackPressTime!) <= timeout) {
      _lastBackPressTime = null;
      return true;
    }
    _lastBackPressTime = now;
    return false;
  }

  /// Resets history state (used by widget/unit tests).
  @visibleForTesting
  void reset() {
    _tabHistory.clear();
    _tabHistory.add('/feed');
    _lastBackPressTime = null;
  }
}
