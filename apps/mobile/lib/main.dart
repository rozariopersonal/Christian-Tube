import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/config/app_config.dart';
import 'core/models/video.dart';
import 'core/services/notification_service.dart';
import 'core/theme/theme_service.dart';
import 'features/auth/auth_service.dart';
import 'features/channels/channel_service.dart';
import 'features/channels/channels_screen.dart';
import 'features/feed/video_feed_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/user_service.dart';
import 'features/search/search_screen.dart';
import 'features/shorts/shorts_feed_screen.dart';
import 'features/watch/video_player_screen.dart';
import 'features/watch_plans/watch_plans_screen.dart';
import 'l10n/app_localizations.dart';
import 'layout/main_layout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  await NotificationService().initialize();
  runApp(const PrivateTubeApp());
}

class PrivateTubeApp extends StatefulWidget {
  const PrivateTubeApp({super.key});

  @override
  State<PrivateTubeApp> createState() => _PrivateTubeAppState();
}

class _PrivateTubeAppState extends State<PrivateTubeApp> {
  final ThemeService _themeService = ThemeService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final ChannelService _channelService = ChannelService();

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _userService.fetchUserData();

    _router = GoRouter(
      initialLocation: '/feed',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return MainLayoutScreen(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/feed',
                  builder: (context, state) => const VideoFeedScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/shorts',
                  builder: (context, state) => const ShortsFeedScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/channels',
                  builder: (context, state) => const ChannelsScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/watch-plans',
                  builder: (context, state) => const WatchPlansScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (context, state) => ProfileScreen(
                    authService: _authService,
                    userService: _userService,
                    channelService: _channelService,
                    themeService: _themeService,
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/watch/:id',
          builder: (context, state) {
            final videoId = state.pathParameters['id'] ?? '';
            final video = state.extra as Video?;
            return VideoPlayerScreen(videoId: videoId, initialVideo: video);
          },
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeService,
      builder: (context, _) {
        return MaterialApp.router(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeService.lightTheme,
          darkTheme: ThemeService.darkTheme,
          themeMode: _themeService.themeMode,
          routerConfig: _router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    );
  }
}
