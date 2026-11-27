import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/playlists/screens/playlists_screen.dart';
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
      duration: '10:00',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PlaylistsScreen empty state, create, rename, delete dialogs and Play All across breakpoints', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');
    var seq = 0;
    final service = PlaylistService.forTesting(
      syncService: sync,
      userId: 'u1',
      idGenerator: () => 'pl-${++seq}',
    );
    await service.init();

    Object? pushedExtra;
    final router = GoRouter(
      initialLocation: '/playlists',
      routes: [
        GoRoute(
          path: '/playlists',
          builder: (_, __) => PlaylistsScreen(playlistService: service),
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
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    }

    // Create playlist via dialog
    await tester.tap(find.text('Create Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Sunday Messages');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Created "Sunday Messages"'), findsOneWidget);
    expect(find.text('Sunday Messages'), findsOneWidget);

    // Add a video to verify Play All & responsive rendering with items
    await service.addVideoToPlaylist('pl-1', _video('v1', 'Message 1'));
    await tester.pumpAndSettle();

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Overflow with item at width $width');
    }

    // Play All
    await tester.tap(find.byTooltip('Play All'));
    await tester.pumpAndSettle();
    expect(find.text('WATCH_PAGE'), findsOneWidget);
    expect((pushedExtra as Map<String, dynamic>)['playlistTitle'], 'Sunday Messages');

    router.pop();
    await tester.pumpAndSettle();

    // Rename playlist
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Renamed Messages');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed playlist to "Renamed Messages"'), findsOneWidget);
    expect(find.text('Renamed Messages'), findsOneWidget);

    // Delete playlist
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted "Renamed Messages"'), findsOneWidget);
    expect(find.text('No playlists yet'), findsOneWidget);

    addTearDown(tester.view.reset);
    service.dispose();
  });
}
