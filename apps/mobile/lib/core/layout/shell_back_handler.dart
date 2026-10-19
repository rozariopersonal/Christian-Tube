import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:go_router/go_router.dart';

import '../navigation/navigation_history_service.dart';
import '../services/bottom_bar_visibility_service.dart';

/// Owns system-back behavior for the navigation shell.
///
/// Implements the Universal Back Standard:
/// 1. Pops pushed subpage / modal route if present on the navigator stack.
/// 2. Handles active player states (e.g. collapses Shorts player to grid).
/// 3. Routes orphaned in-shell subpages to their logical parent screen.
/// 4. Unwinds root-tab history (e.g. Audio -> Bible -> Feed).
/// 5. Displays a double-tap exit confirmation before terminating from the Home feed.
class ShellBackHandler extends StatelessWidget {
  final String path;
  final Widget child;

  const ShellBackHandler({super.key, required this.path, required this.child});

  static final List<bool Function()> _interceptors = [];

  /// Registers an active in-shell back interceptor (e.g. for sheets, selection, modals).
  ///
  /// Interceptors are called in reverse order (most recently registered first).
  /// If an interceptor returns `true`, the back event is considered handled and
  /// back processing terminates immediately.
  static VoidCallback registerInterceptor(bool Function() interceptor) {
    _interceptors.add(interceptor);
    return () => _interceptors.remove(interceptor);
  }

  @visibleForTesting
  static void resetInterceptors() => _interceptors.clear();

  void _handleBack(BuildContext context) {
    // 0. Active in-shell overlays / dialogs / sheets (AGENTS.md Hierarchy step 1)
    for (final interceptor in _interceptors.reversed.toList()) {
      if (interceptor()) {
        return;
      }
    }

    // 1. If an inner route can pop on the active navigator, pop it first.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    try {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
        return;
      }
    } catch (_) {
      // In case GoRouter is not available in isolated widget tests.
    }

    // 2. Media state overrides (Shorts player open -> collapse to grid).
    if (path.startsWith('/shorts')) {
      final service = BottomBarVisibilityService.instance;
      if (service.isShortPlaying) {
        service.requestShortsReset();
        return;
      }
    }


    // Bible reader bottom bar override (if main tab nav was hidden on scroll, restore it first).
    if (path.startsWith('/bible')) {
      final service = BottomBarVisibilityService.instance;
      if (service.isBibleNavHidden) {
        service.showBibleNav();
        return;
      }
    }

    // 3. In-shell subpage fallback routing (when entered via direct replace/deep link).
    if (path.startsWith('/channels') ||
        path.startsWith('/search') ||
        path.startsWith('/watch')) {
      context.go('/feed');
      return;
    }
    if (path.startsWith('/article/')) {
      context.go('/articles');
      return;
    }
    if (path.startsWith('/song/')) {
      context.go('/songs');
      return;
    }
    if (path.startsWith('/books/')) {
      context.go('/books');
      return;
    }
    if (path.startsWith('/books') ||
        path.startsWith('/articles') ||
        path.startsWith('/songs')) {
      context.go('/library');
      return;
    }
    if (path.startsWith('/audio/series')) {
      context.go('/audio');
      return;
    }
    if (path.startsWith('/watch-plans') ||
        path.startsWith('/downloads') ||
        path.startsWith('/bible-manager') ||
        path.startsWith('/history') ||
        path.startsWith('/settings') ||
        path.startsWith('/admin-users') ||
        path.startsWith('/subscriptions') ||
        path.startsWith('/saved-scriptures') ||
        path.startsWith('/playlists')) {
      context.go('/profile');
      return;
    }

    // 4. Tab history unwind (e.g. Feed -> Bible -> Audio unwinds Audio -> Bible -> Feed).
    final prevTab = NavigationHistoryService.instance.popPreviousTab();
    if (prevTab != null && prevTab != path) {
      context.go(prevTab);
      return;
    }

    // 5. If not on the Home feed root, return to Home.
    if (path != '/feed') {
      context.go('/feed');
      return;
    }

    // 6. On Home (/feed) with empty history: prompt double-tap exit before closing.
    final shouldExit = NavigationHistoryService.instance.shouldExitOnDoubleBack();
    if (shouldExit) {
      SystemNavigator.pop();
    } else {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (_) {
        // Fallback for tests without ScaffoldMessenger
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: child,
    );
  }
}
