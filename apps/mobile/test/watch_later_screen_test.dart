import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/playlists/screens/watch_later_screen.dart';
import 'package:mobile/features/playlists/services/watch_later_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData _testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

Video _video(String id, String title) => Video(
      id: id,
      title: title,
      thumbnailUrl: '',
      channelId: 'ch1',
      channelTitle: 'Grace Fellowship',
      publishedAt: DateTime(2025, 1, 1),
      duration: '14:20',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('WatchLaterScreen renders without overflow at 320/600/840/1400 and shows empty state', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    final service = WatchLaterService.forTesting(syncService: sync, userId: 'u1');
    await service.init();

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: WatchLaterScreen(watchLaterService: service),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Overflow at width $width');
      expect(find.text('No videos in Watch Later'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    }

    addTearDown(tester.view.reset);
    service.dispose();
  });

  testWidgets('WatchLaterScreen Play All and remove with snackbar at all breakpoints', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');
    final service = WatchLaterService.forTesting(syncService: sync, userId: 'u1');
    await service.init();
    await service.toggleWatchLater(_video('v1', 'Sermon on Hope'));
    await service.toggleWatchLater(_video('v2', 'Sermon on Faith'));

    Object? pushedExtra;
    final router = GoRouter(
      initialLocation: '/watch-later',
      routes: [
        GoRoute(
          path: '/watch-later',
          builder: (_, __) => WatchLaterScreen(watchLaterService: service),
        ),
        GoRoute(
          path: '/watch/:id',
          builder: (_, state) {
            pushedExtra = state.extra;
            return const Scaffold(body: Text('WATCH_PAGE'));
          },
        ),
      ],
    );

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp.router(theme: _testTheme(), routerConfig: router),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Overflow at width $width');
    }

    // Test Play All
    await tester.tap(find.text('Play All'));
    await tester.pumpAndSettle();
    expect(find.text('WATCH_PAGE'), findsOneWidget);
    final extraMap = pushedExtra as Map<String, dynamic>;
    expect(extraMap['playlistTitle'], 'Watch Later');
    expect((extraMap['playlist'] as List).length, 2);

    // Pop back and remove first video
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove from Watch Later').first);
    await tester.pumpAndSettle();

    expect(find.text('Removed from Watch Later'), findsOneWidget);
    expect(service.count, 1);

    addTearDown(tester.view.reset);
    service.dispose();
  });
}
