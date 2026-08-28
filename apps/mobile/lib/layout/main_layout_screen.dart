import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/engines/active_engine.g.dart';
import '../core/services/bottom_bar_visibility_service.dart';
import '../features/shorts/players/shorts_player.dart';
import '../features/update/update_service.dart';

class MainLayoutScreen extends StatefulWidget {
  final Widget child;
  final StatefulNavigationShell? navigationShell;

  const MainLayoutScreen({
    super.key,
    required this.child,
    this.navigationShell,
  });

  const MainLayoutScreen.shell({
    super.key,
    required StatefulNavigationShell navigationShell,
  })  : child = navigationShell,
        navigationShell = navigationShell;

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
    if (widget.navigationShell != null) {
      _lastSelectedTabIndex = widget.navigationShell!.currentIndex;
      return _lastSelectedTabIndex;
    }

    if (currentPath.startsWith('/feed')) {
      _lastSelectedTabIndex = 0;
    } else if (currentPath.startsWith('/shorts')) {
      _lastSelectedTabIndex = 1;
    } else if (kMicroFeedEnabled && currentPath.startsWith('/words')) {
      _lastSelectedTabIndex = 2;
    } else if (currentPath.startsWith('/channels')) {
      _lastSelectedTabIndex = kMicroFeedEnabled ? 3 : 2;
    } else if (currentPath.startsWith('/profile')) {
      _lastSelectedTabIndex = kMicroFeedEnabled ? 4 : 3;
    }

    return _lastSelectedTabIndex;
  }

  void _onTabSelected(int index) {
    if (index != 1) {
      stopAllPlatformShorts();
    }

    if (widget.navigationShell != null) {
      widget.navigationShell!.goBranch(
        index,
        initialLocation: index == widget.navigationShell!.currentIndex,
      );
      return;
    }

    // Direct navigation fallback
    switch (index) {
      case 0:
        context.go('/feed');
        break;
      case 1:
        context.go('/shorts');
        break;
      case 2:
        if (kMicroFeedEnabled) {
          context.go('/words');
        } else {
          context.go('/channels');
        }
        break;
      case 3:
        if (kMicroFeedEnabled) {
          context.go('/channels');
        } else {
          context.go('/profile');
        }
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white70 : Colors.black54),
                      );
                    }),
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      final isSelected = states.contains(WidgetState.selected);
                      return IconThemeData(
                        size: 24,
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white70 : Colors.black54),
                      );
                    }),
                  ),
                  child: NavigationBar(
                    selectedIndex: selectedIndex,
                    backgroundColor: isDark ? Colors.black : Colors.white,
                    elevation: 0,
                    onDestinationSelected: _onTabSelected,
                    destinations: [
                      const NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_filled),
                        label: 'Home',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.bolt_outlined),
                        selectedIcon: Icon(Icons.bolt),
                        label: 'Shorts',
                      ),
                      if (kMicroFeedEnabled)
                        const NavigationDestination(
                          icon: Icon(Icons.auto_awesome_outlined),
                          selectedIcon: Icon(Icons.auto_awesome),
                          label: 'Words',
                        ),
                      const NavigationDestination(
                        icon: Icon(Icons.subscriptions_outlined),
                        selectedIcon: Icon(Icons.subscriptions),
                        label: 'Subscriptions',
                      ),
                      const NavigationDestination(
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
