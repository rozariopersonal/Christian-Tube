import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:go_router/go_router.dart';

import '../services/bottom_bar_visibility_service.dart';

/// Owns system-back behavior for the navigation shell.
///
/// When the shell's inner navigator has nothing to pop (the common root-tab
/// case), go_router hands system back to the *root* navigator. A [PopScope]
/// placed inside a shell child route is therefore never consulted there, so
/// this widget must be mounted from the shell builder to register against the
/// shell page route and decide where back takes the user for each root tab.
class ShellBackHandler extends StatelessWidget {
  final String path;
  final Widget child;

  const ShellBackHandler({super.key, required this.path, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (path.startsWith('/shorts')) {
          final service = BottomBarVisibilityService.instance;
          if (service.isShortPlaying) {
            // A Short is playing: collapse the fullscreen player back to the
            // Shorts grid rather than leaving the branch or exiting the app.
            service.requestShortsReset();
          } else {
            // Shorts grid on a root tab: return to the Videos home feed.
            context.go('/feed');
          }
          return;
        }
        // Other root tabs keep the platform default back behavior (exit on
        // Android), which is what the shell previously produced.
        SystemNavigator.pop();
      },
      child: child,
    );
  }
}
