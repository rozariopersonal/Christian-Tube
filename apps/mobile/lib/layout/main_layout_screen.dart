import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/engines/active_engine.g.dart';
import '../core/layout/adaptivity.dart';
import '../core/services/bottom_bar_visibility_service.dart';
import '../core/theme/app_tokens.dart';
import '../core/config/app_config.dart';
import '../features/auth/auth_service.dart';
import '../features/shorts/players/shorts_player.dart';
import '../features/update/update_service.dart';

class MainLayoutScreen extends StatefulWidget {
  final Widget child;
  final AuthService authService;
  const MainLayoutScreen({
    super.key,
    required this.child,
    required this.authService,
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
    if (kIsWeb) return;
    // Wait for the root navigator and initial frame to settle
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final updateData = await UpdateService.checkForUpdate();
    if (updateData != null && mounted) {
      UpdateService.showUpdatePopup(context, updateData);
    }
  }

  bool get _isBibleTabEnabled {
    return AppConfig.instanceId != 'centum_academy';
  }

  bool get _isBooksTabEnabled {
    return AppConfig.instanceId != 'centum_academy';
  }

  int _getSelectedIndex(String currentPath) {
    // Build the destination paths in the same order they appear in the bar.
    final destinations = _destinationPaths();
    for (var i = 0; i < destinations.length; i++) {
      final path = destinations[i];
      if (currentPath.startsWith(path)) {
        _lastSelectedTabIndex = i;
        break;
      }
    }
    return _lastSelectedTabIndex;
  }

  /// The route path each tab index navigates to, in bar order.
  List<String> _destinationPaths() {
    return [
      '/feed',
      '/shorts',
      if (_isBibleTabEnabled) '/bible',
      if (_isBooksTabEnabled) '/books',
      if (kMicroFeedEnabled) '/words',
      '/profile',
    ];
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
    final wordsIndex = _destinationPaths().indexOf('/words');
    if (wordsIndex != -1 && index == wordsIndex) {
      BottomBarVisibilityService.instance.requestWordsReset();
    }

    // Direct navigation using the same dynamic path list as the bar.
    final destinations = _destinationPaths();
    if (index < 0 || index >= destinations.length) return;
    context.go(destinations[index]);
  }

  List<_NavSpec> _destinations(BuildContext context) {
    return [
      const _NavSpec(
        label: 'Videos',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_filled,
      ),
      const _NavSpec(
        label: 'Shorts',
        icon: Icons.bolt_outlined,
        selectedIcon: Icons.bolt,
      ),
      if (_isBibleTabEnabled)
        const _NavSpec(
          label: 'Bible',
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book,
        ),
      if (_isBooksTabEnabled)
        const _NavSpec(
          label: 'Books',
          icon: Icons.auto_stories_outlined,
          selectedIcon: Icons.auto_stories,
        ),
      if (kMicroFeedEnabled)
        const _NavSpec(
          label: 'Words',
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome,
        ),
      _NavSpec(
        label: 'You',
        iconBuilder: () => _buildProfileAvatar(context, 64 * 0.66),
        selectedIconBuilder: () => _buildProfileAvatar(context, 64 * 0.66),
      ),
    ];
  }

  Widget _buildProfileAvatar(BuildContext context, double size) {
    final user = widget.authService.currentUser;
    final tokens = Theme.of(context).extension<AppTokens>();
    final fallbackColor = tokens?.onSurface ?? Theme.of(context).colorScheme.onSurface;

    if (user != null && user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: CachedNetworkImage(
            imageUrl: user.photoUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Icon(
              Icons.account_circle,
              size: size,
              color: fallbackColor,
            ),
          ),
        ),
      );
    }

    // Fallback: initial of the display name, or a generic account icon.
    final initial = (user?.displayName.isNotEmpty ?? false)
        ? user!.displayName[0].toUpperCase()
        : null;
    if (initial != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Text(
          initial,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Icon(
      Icons.account_circle_outlined,
      size: size,
      color: fallbackColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<AppTokens>();
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _getSelectedIndex(currentPath);

    return ListenableBuilder(
      listenable: Listenable.merge(
          [BottomBarVisibilityService.instance, widget.authService]),
      builder: (context, _) {
        final service = BottomBarVisibilityService.instance;
        final size = MediaQuery.sizeOf(context);
        final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
        final navMode = resolveNavMode(
          width: size.width,
          isLandscape: isLandscape,
          isShortPlaying: service.isShortPlaying,
          isExplicitlyHidden: service.isExplicitlyHidden,
          isWatchRoute: currentPath.startsWith('/watch'),
          isWeb: kIsWeb,
        );

        switch (navMode) {
          case AppNavMode.bottomBar:
            return Scaffold(
              body: widget.child,
              bottomNavigationBar: _buildBottomBar(isDark, selectedIndex),
            );
          case AppNavMode.rail:
            return Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNavigationRail(isDark, selectedIndex),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: tokens?.surfaceBorder ?? theme.dividerColor,
                  ),
                  Expanded(child: widget.child),
                ],
              ),
            );
          case AppNavMode.hidden:
            return Scaffold(body: widget.child);
        }
      },
    );
  }

  Widget _buildBottomBar(bool isDark, int selectedIndex) {
    return NavigationBarTheme(
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
        destinations: _destinations(context)
            .map(
              (d) => NavigationDestination(
                icon: d.iconBuilder != null ? d.iconBuilder!() : Icon(d.icon),
                selectedIcon: d.selectedIconBuilder != null
                    ? d.selectedIconBuilder!()
                    : Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildNavigationRail(bool isDark, int selectedIndex) {
    final tokens = Theme.of(context).extension<AppTokens>();
    final background = tokens?.background ?? (isDark ? Colors.black : Colors.white);
    final selectedColor = isDark ? Colors.white : Colors.black;
    final unselectedColor = isDark ? Colors.white70 : Colors.black54;
    final indicator = tokens?.surfaceVariant ?? (isDark ? Colors.grey.shade800 : Colors.grey.shade200);

    return NavigationRail(
      backgroundColor: background,
      selectedIndex: selectedIndex,
      onDestinationSelected: _onTabSelected,
      labelType: NavigationRailLabelType.all,
      minWidth: 76,
      indicatorColor: indicator,
      selectedIconTheme: IconThemeData(color: selectedColor),
      unselectedIconTheme: IconThemeData(color: unselectedColor),
      selectedLabelTextStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: selectedColor,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 11,
        color: unselectedColor,
      ),
      destinations: _destinations(context)
          .map(
            (d) => NavigationRailDestination(
              icon: d.iconBuilder != null ? d.iconBuilder!() : Icon(d.icon),
              selectedIcon: d.selectedIconBuilder != null
                  ? d.selectedIconBuilder!()
                  : Icon(d.selectedIcon),
              label: Text(d.label),
            ),
          )
          .toList(),
    );
  }
}

class _NavSpec {
  final String label;
  final IconData? icon;
  final IconData? selectedIcon;
  final Widget Function()? iconBuilder;
  final Widget Function()? selectedIconBuilder;

  const _NavSpec({
    required this.label,
    this.icon,
    this.selectedIcon,
    this.iconBuilder,
    this.selectedIconBuilder,
  });
}