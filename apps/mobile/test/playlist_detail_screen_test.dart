import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/playlists/screens/playlist_detail_screen.dart';
import 'package:mobile/features/playlists/services/playlist_service.dart';
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
      channelTitle: 'Grace Church',
      publishedAt: DateTime(2025, 1, 1),
      duration: '11:00',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PlaylistDetailScreen deep-link safe, responsive 320/600/840/1400, Play All, remove, edit, delete', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');
    final service = PlaylistService.forTesting(
      syncService: sync,
      userId: 'u1',
      idGenerator: () => 'pl-1',
    );
    await service.init();
    await service.createPlaylist(
      'Bible Study',
      description: 'Romans series',
      initialVideo: _video('v1', 'Romans 1'),
    );
    await service.addVideoToPlaylist('pl-1', _video('v2', 'Romans 2'));

    Object? pushedExtra;
    final router = GoRouter(
      initialLocation: '/playlists/pl-1',
      routes: [
        GoRoute(
          path: '/playlists',
          builder: (_, __) => const Scaffold(body: Text('PLAYLISTS_HUB')),
        ),
        GoRoute(
          path: '/playlists/:id',
          builder: (_, state) => PlaylistDetailScreen(
            playlistId: state.pathParameters['id'] ?? '',
            playlistService: service,
          ),
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
      expect(find.text('Bible Study'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    }

    // Play All
    await tester.tap(find.text('Play All'));
    await tester.pumpAndSettle();
    expect(find.text('WATCH_PAGE'), findsOneWidget);
    expect((pushedExtra as Map<String, dynamic>)['playlistTitle'], 'Bible Study');

    router.pop();
    await tester.pumpAndSettle();

    // Remove a video
    await tester.tap(find.byTooltip('Remove from playlist').first);
    await tester.pumpAndSettle();
    expect(find.text('Removed from Bible Study'), findsOneWidget);
    expect(service.getById('pl-1')?.videos.length, 1);

    // Edit playlist
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Romans Deep Dive');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Updated playlist'), findsOneWidget);
    expect(find.text('Romans Deep Dive'), findsOneWidget);

    // Delete playlist
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYLISTS_HUB'), findsOneWidget);

    addTearDown(tester.view.reset);
    service.dispose();
  });

  testWidgets('PlaylistDetailScreen renders not-found state for unknown id', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    final service = PlaylistService.forTesting(syncService: sync, userId: 'u1');
    await service.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(),
        home: PlaylistDetailScreen(
          playlistId: 'does-not-exist',
          playlistService: service,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Playlist not found'), findsOneWidget);

    service.dispose();
  });
}
