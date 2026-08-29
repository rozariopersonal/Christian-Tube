import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/config/app_config.dart';
import 'core/engines/active_engine.g.dart';
import 'core/models/video.dart';
import 'core/services/notification_service.dart';
import 'core/theme/theme_service.dart';
import 'features/auth/auth_service.dart';
import 'features/channels/channel_service.dart';
import 'features/channels/channels_screen.dart';
import 'features/engines/scripture/screens/bible_manager_screen.dart';
import 'features/engines/scripture/services/bible_download_manager.dart';
import 'features/feed/video_feed_screen.dart';
import 'features/micro_feed/micro_feed_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/user_service.dart';
import 'features/search/search_screen.dart';
import 'features/shorts/shorts_feed_screen.dart';
import 'features/watch/video_player_screen.dart';
import 'features/watch_plans/watch_plans_screen.dart';
import 'features/bible/screens/bible_screen.dart';
import 'l10n/app_localizations.dart';
import 'layout/main_layout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();

  // Run secondary initializations in background to eliminate startup blank screen
  NotificationService().initialize().catchError((e) => debugPrint('Notification init error: $e'));
  // Ensure the default bible (TAOBVSI) starts downloading right away so the
  // Words feed and Bible page have text even if the user never opens the
  // scripture engine first.
  BibleDownloadManager().ensureDefaultInstalled()
      .catchError((e) => debugPrint('Default bible download error: $e'));
  if (kMicroFeedEnabled) {
    try {
      final engine = createActiveFeedEngine();
      engine?.initialize().catchError((e) => debugPrint('Engine init error: $e'));
    } catch (_) {}
  }

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
        ShellRoute(
          builder: (context, state, child) {
            return MainLayoutScreen(child: child);
          },
          routes: [
            GoRoute(
              path: '/feed',
              builder: (context, state) => const VideoFeedScreen(),
            ),
            GoRoute(
              path: '/shorts',
              builder: (context, state) {
                final shortId = state.uri.queryParameters['id'] ??
                    state.uri.queryParameters['videoId'] ??
                    (state.extra as Map<String, dynamic>?)?['shortId'] as String?;
                final initialIndex = (state.extra as Map<String, dynamic>?)?['initialIndex'] as int?;
                return ShortsFeedScreen(
                  initialShortId: shortId,
                  initialIndex: initialIndex,
                );
              },
            ),
            GoRoute(
              path: '/bible',
              builder: (context, state) => const BibleScreen(),
            ),
            if (kMicroFeedEnabled)
              GoRoute(
                path: '/words',
                builder: (context, state) {
                  final engine = createActiveFeedEngine();
                  return engine != null
                      ? MicroFeedScreen(engine: engine)
                      : const SizedBox.shrink();
                },
              ),
            GoRoute(
              path: '/channels',
              builder: (context, state) => const ChannelsScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => ProfileScreen(
                authService: _authService,
                userService: _userService,
                channelService: _channelService,
                themeService: _themeService,
              ),
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
                final startSec = double.tryParse(state.uri.queryParameters['start'] ?? '') ??
                    (extraMap?['start'] as num?)?.toDouble();

                return VideoPlayerScreen(
                  videoId: videoId,
                  initialVideo: video,
                  playlist: playlist,
                  playlistTitle: playlistTitle,
                  initialPlaylistIndex: initialIndex,
                  startSeconds: startSec,
                );
              },
            ),
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
            GoRoute(
              path: '/watch-plans',
              builder: (context, state) => const WatchPlansScreen(),
            ),
            GoRoute(
              path: '/bible-manager',
              builder: (context, state) => const BibleManagerScreen(),
            ),
          ],
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
