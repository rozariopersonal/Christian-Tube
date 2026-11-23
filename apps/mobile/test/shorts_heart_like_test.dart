import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/short.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/shorts/widgets/community_shorts_grid.dart';
import 'package:mobile/features/shorts/widgets/short_action_bar.dart';
import 'package:mobile/features/shorts/widgets/short_player_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData _testTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      extensions: const [AppTokens.light],
    );

Short _sampleShort() => Short(
      id: 'short_1',
      title: 'Faith Short',
      videoUrl: 'https://www.youtube.com/shorts/short_1',
      thumbnailUrl: 'https://example.com/short_1.jpg',
      channelId: 'ch_1',
      channelTitle: 'Grace Chapel',
      publishedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await UserSyncService.instance.onUserChanged(null);
  });

  testWidgets('ShortActionBar renders heart icon without hand icon or counts',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(),
        home: Scaffold(
          body: ShortActionBar(
            short: _sampleShort(),
            onShare: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.text('Like'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_rounded), findsNothing);
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);

    await tester.tap(find.text('Like'));
    await tester.pump();
    expect(find.text('Sign in to save liked Shorts'), findsOneWidget);
  });

  testWidgets('ShortPlayerOverlay double-tap invokes onDoubleTapLike and renders burst',
      (tester) async {
    var doubleTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(),
        home: Scaffold(
          body: ShortPlayerOverlay(
            isNonPlayableLocalShort: false,
            showPlayPauseOverlay: false,
            playPauseOverlayPlaying: true,
            onScreenTap: () {},
            areControlsVisible: true,
            short: _sampleShort(),
            showLikeBurst: true,
            onDoubleTapLike: () => doubleTapped = true,
            onShare: () {},
            isScrubbing: false,
            currentPosition: 0,
            totalDuration: 60,
            onStopAllPlatformShorts: () {},
            onPushRoute: (_) {},
            onShowDetailsSheet: () {},
            onPanStart: (_) {},
            onPanUpdate: (_) {},
            onPanEnd: (_) {},
            verticalRailHeightFactor: 0.5,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    expect(doubleTapped, isTrue);
  });

  testWidgets('CommunityShortsGrid uses heart icon on Liked filter chip',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(),
        home: Scaffold(
          body: CommunityShortsGrid(
            allShorts: const [],
            filteredShorts: const [],
            scrollController: controller,
            onRefresh: () async {},
            isLoadingMore: false,
            onShortTap: (_) {},
            filterChannels: const [],
            selectedChannelIds: const {},
            onChannelFilterTap: () {},
            likedOnly: false,
            onLikedOnlyChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Liked'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsNothing);
  });
}
