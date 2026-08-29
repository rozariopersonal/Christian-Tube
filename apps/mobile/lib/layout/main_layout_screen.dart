import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/engines/active_engine.g.dart';
import '../core/services/bottom_bar_visibility_service.dart';
import '../core/theme/app_tokens.dart';
import '../features/shorts/players/shorts_player.dart';
import '../features/update/update_service.dart';

class MainLayoutScreen extends StatefulWidget {
  final Widget child;
  const MainLayoutScreen({
    super.key,
    required this.child,
  });

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _lastSelectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkAutoUpdate();
  }

  Future<void> _checkAutoUpdate() async {
    // Wait for the root navigator and initial frame to settle
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final updateData = await UpdateService.checkForUpdate();
    if (updateData != null && mounted) {
      UpdateService.showUpdatePopup(context, updateData);
    }
  }

  int _getSelectedIndex(String currentPath) {
    if (currentPath.startsWith('/feed')) {
      _lastSelectedTabIndex = 0;
    } else if (currentPath.startsWith('/shorts')) {
      _lastSelectedTabIndex = 1;
    } else if (currentPath.startsWith('/bible')) {
      _lastSelectedTabIndex = 2;
    } else if (kMicroFeedEnabled && currentPath.startsWith('/words')) {
      _lastSelectedTabIndex = 3;
    } else if (currentPath.startsWith('/channels')) {
      _lastSelectedTabIndex = kMicroFeedEnabled ? 4 : 3;
    } else if (currentPath.startsWith('/profile')) {
      _lastSelectedTabIndex = kMicroFeedEnabled ? 5 : 4;
    }

    return _lastSelectedTabIndex;
  }

  void _onTabSelected(int index) {
    if (index != 1) {
      stopAllPlatformShorts();
    }

    if (index == 1 && _lastSelectedTabIndex == 1) {
      BottomBarVisibilityService.instance.requestShortsReset();
      return;
    }

    // Always reset the Words feed to a new random list when navigated
    if (kMicroFeedEnabled && index == 3) {
      BottomBarVisibilityService.instance.requestWordsReset();
    }

    // Direct navigation
    switch (index) {
      case 0:
        context.go('/feed');
        break;
      case 1:
        context.go('/shorts');
        break;
      case 2:
        context.go('/bible');
        break;
      case 3:
        if (kMicroFeedEnabled) {
          context.go('/words');
        } else {
          context.go('/channels');
        }
        break;
      case 4:
        if (kMicroFeedEnabled) {
          context.go('/channels');
        } else {
          context.go('/profile');
        }
        break;
      case 5:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _getSelectedIndex(currentPath);

    return ListenableBuilder(
      listenable: BottomBarVisibilityService.instance,
      builder: (context, _) {
        final shouldShowBottomNav = BottomBarVisibilityService.instance.shouldShow(
          context: context,
          currentPath: currentPath,
          selectedIndex: selectedIndex,
        );

        return Scaffold(
          body: widget.child,
          bottomNavigationBar: shouldShowBottomNav
              ? NavigationBarTheme(
                  data: NavigationBarThemeData(
                    height: 60,
                    indicatorColor: Colors.transparent,
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      final isSelected = states.contains(WidgetState.selected);
                      return TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? tokens.onSurface
                            : tokens.onSurfaceMuted,
                      );
                    }),
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      final isSelected = states.contains(WidgetState.selected);
                      return IconThemeData(
                        size: 24,
                        color: isSelected
                            ? tokens.onSurface
                            : tokens.onSurfaceMuted,
                      );
                    }),
                  ),
                  child: NavigationBar(
                    selectedIndex: selectedIndex,
                    backgroundColor: tokens.surface,
                    elevation: 0,
                    onDestinationSelected: _onTabSelected,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_filled),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bolt_outlined),
                        selectedIcon: Icon(Icons.bolt),
                        label: 'Shorts',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.menu_book_outlined),
                        selectedIcon: Icon(Icons.menu_book),
                        label: 'Bible',
                      ),
                      if (kMicroFeedEnabled)
                        NavigationDestination(
                          icon: Icon(Icons.auto_awesome_outlined),
                          selectedIcon: Icon(Icons.auto_awesome),
                          label: 'Words',
                        ),
                      NavigationDestination(
                        icon: Icon(Icons.subscriptions_outlined),
                        selectedIcon: Icon(Icons.subscriptions),
                        label: 'Subscriptions',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.account_circle_outlined),
                        selectedIcon: Icon(Icons.account_circle),
                        label: 'You',
                      ),
                    ],
                  ),
                )
              : null,
        );
      },
    );
  }
}
