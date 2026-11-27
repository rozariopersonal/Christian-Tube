import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/playlists/services/playlist_service.dart';
import 'package:mobile/features/playlists/services/watch_later_service.dart';
import 'package:mobile/features/playlists/widgets/save_to_playlist_sheet.dart';
import 'package:mobile/features/watch/widgets/video_action_bar.dart';
import 'package:mobile/shared/ui/recommendation_video_card.dart';
import 'package:mobile/shared/ui/search_video_card.dart';
import 'package:mobile/shared/ui/video_options_bottom_sheet.dart';
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
      duration: '15:00',
      viewCount: 1200,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SaveToPlaylistSheet toggles Watch Later, playlists, and creates inline playlist with snackbars', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');
    final wl = WatchLaterService.forTesting(syncService: sync, userId: 'u1');
    final pl = PlaylistService.forTesting(
      syncService: sync,
      userId: 'u1',
      idGenerator: () => 'pl-new',
    );
    await wl.init();
    await pl.init();
    await pl.createPlaylist('Favorites');

    final video = _video('v1', 'Grace Message');

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => SaveToPlaylistSheet.show(
                    context,
                    video: video,
                    watchLaterService: wl,
                    playlistService: pl,
                  ),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Overflow at width $width');

      Navigator.of(tester.element(find.byType(SaveToPlaylistSheet))).pop();
      await tester.pumpAndSettle();
    }

    // Reopen at 360dp to test full interactions
    tester.view.physicalSize = const Size(360, 800);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Toggle Watch Later on -> inline pill + snackbar
    await tester.tap(find.text('Watch Later'));
    await tester.pumpAndSettle();
    expect(wl.isWatchLater('v1'), isTrue);
    expect(find.text('Saved to Watch Later'), findsAtLeastNWidgets(1));

    // Toggle Watch Later off -> inline pill + snackbar
    await tester.tap(find.text('Watch Later'));
    await tester.pumpAndSettle();
    expect(wl.isWatchLater('v1'), isFalse);
    expect(find.text('Removed from Watch Later'), findsAtLeastNWidgets(1));

    // Toggle Favorites playlist on & off
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(pl.isVideoInAnyPlaylist('v1'), isTrue);
    expect(find.text('Added to Favorites'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(pl.isVideoInAnyPlaylist('v1'), isFalse);
    expect(find.text('Removed from Favorites'), findsAtLeastNWidgets(1));

    // Inline + New Playlist form
    await tester.tap(find.text('New Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening Study');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Created "Evening Study" and added video'), findsAtLeastNWidgets(1));
    expect(pl.isVideoInAnyPlaylist('v1'), isTrue);

    addTearDown(tester.view.reset);
    wl.dispose();
    pl.dispose();
  });

  testWidgets('VideoOptionsBottomSheet 1-tap Watch Later, VideoActionBar isSaved, and cards at 320dp', (tester) async {
    final sync = UserSyncService.forTesting(dio: Dio(), canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');
    final wl = WatchLaterService.forTesting(syncService: sync, userId: 'u1');
    final pl = PlaylistService.forTesting(syncService: sync, userId: 'u1');
    await wl.init();
    await pl.init();

    final video = _video('v1', 'A Very Long Sermon Title That Should Not Overflow At 320dp');

    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              SearchVideoCard(video: video),
              RecommendationVideoCard(video: video),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: VideoActionBar(
                  isLiked: false,
                  onToggleLike: () {},
                  onClip: () {},
                  onShare: () {},
                  onSave: () {},
                  isSaved: true,
                  onOpenYouTube: () {},
                ),
              ),
              Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => VideoOptionsBottomSheet.show(
                    context,
                    video: video,
                    watchLaterService: wl,
                    playlistService: pl,
                  ),
                  child: const Text('Options'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byTooltip('More options'), findsNWidgets(2));

    // Open VideoOptionsBottomSheet and tap Save to Watch Later
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Save to Watch Later'), findsOneWidget);
    await tester.tap(find.text('Save to Watch Later'));
    await tester.pumpAndSettle();
    expect(wl.isWatchLater('v1'), isTrue);
    expect(find.text('Saved to Watch Later'), findsOneWidget);

    addTearDown(tester.view.reset);
    wl.dispose();
    pl.dispose();
  });
}
