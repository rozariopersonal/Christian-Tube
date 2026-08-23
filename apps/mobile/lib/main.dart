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
            // Tab 1: Home Feed (Subscribed only)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/feed',
                  builder: (context, state) => const VideoFeedScreen(),
                ),
              ],
            ),
            // Tab 2: Channels (Browse & Subscribe for Users / Manage & Requests for Admin)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/channels',
                  builder: (context, state) => const ChannelsScreen(),
                ),
              ],
            ),
            // Tab 3: Watch Plans & Playlists
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/watch-plans',
                  builder: (context, state) => const WatchPlansScreen(),
                ),
              ],
            ),
            // Tab 4: Profile / Settings
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
            final extraMap = state.extra as Map<String, dynamic>?;
            final video = extraMap?['video'] as Video?;
            final playlist = extraMap?['playlist'] as List<Video>?;
            final playlistTitle = extraMap?['playlistTitle'] as String?;
            final initialIndex = extraMap?['initialIndex'] as int? ?? 0;

            return VideoPlayerScreen(
              videoId: videoId,
              initialVideo: video,
              playlist: playlist,
              playlistTitle: playlistTitle,
              initialPlaylistIndex: initialIndex,
            );
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
          theme: _themeService.lightTheme,
          darkTheme: _themeService.darkTheme,
          themeMode: _themeService.themeMode,
          locale: _themeService.locale,
          routerConfig: _router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    );
  }
}
