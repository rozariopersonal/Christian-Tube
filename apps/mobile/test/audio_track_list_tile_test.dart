import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/audio/controllers/audio_player_controller.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/models/playback_state.dart';
import 'package:mobile/features/audio/widgets/audio_track_list_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testTrackLongTitle = AudioTrack(
    id: 'track_long_1',
    title:
        '01 - The Great Mystery of Godliness: Christ Manifest in the Flesh and Justified in the Spirit for Our Complete Deliverance',
    seriesId: 'series_1',
    seriesTitle: 'The Christian Life',
    speaker: 'Zac Poonen',
    durationSeconds: 3120, // 52:00
    audioUrl: 'https://example.com/audio1.mp3',
    scriptureBook: '1TI',
    scriptureChapter: 3,
    scriptureVerse: 16,
  );

  Widget buildTileHarness({
    required AudioTrack track,
    int savedPosition = 0,
    bool isPlaying = false,
  }) {
    if (isPlaying) {
      AudioPlayerController.instance.setStateForTesting(AudioPlayerState(
        currentTrack: track,
        queue: [track],
        queueIndex: 0,
        status: AudioPlaybackStatus.playing,
      ));
    } else {
      AudioPlayerController.instance.setStateForTesting(const AudioPlayerState());
    }

    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [AppTokens.dark],
      ),
      home: Scaffold(
        body: ListView(
          children: [
            AudioTrackListTile(
              track: track,
              index: 0,
              savedPositionSeconds: savedPosition,
              queue: [track],
            ),
          ],
        ),
      ),
    );
  }

  group('AudioTrackListTile Option 2 Layout & Unclipped Titles', () {
    testWidgets('renders full long title across multiple lines without overflow at 320px',
        (tester) async {
      setSurfaceSize(tester, 320, 600);

      await tester.pumpWidget(buildTileHarness(track: testTrackLongTitle));
      await tester.pumpAndSettle();

      // Ensure the complete title is rendered in the widget tree
      expect(
        find.text(
          '01 - The Great Mystery of Godliness: Christ Manifest in the Flesh and Justified in the Spirit for Our Complete Deliverance',
        ),
        findsOneWidget,
      );

      // Verify maxLines is 3 (not clipped to 1 line)
      final textWidget = tester.widget<Text>(find.text(
        '01 - The Great Mystery of Godliness: Christ Manifest in the Flesh and Justified in the Spirit for Our Complete Deliverance',
      ));
      expect(textWidget.maxLines, 3);
      expect(textWidget.softWrap, isTrue);

      // Verify duration and scripture tag are rendered
      expect(find.text('52:00'), findsOneWidget);
      expect(find.text('1TI 3:16'), findsOneWidget);

      // Verify slim play button is present in trailing
      expect(find.byIcon(Icons.play_circle_rounded), findsOneWidget);

      // Advance timers to clear any debounced savePosition timers
      await tester.pump(const Duration(seconds: 4));

      // Zero layout overflow exceptions
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders resume position when savedPosition is present', (tester) async {
      setSurfaceSize(tester, 360, 600);

      await tester.pumpWidget(
        buildTileHarness(track: testTrackLongTitle, savedPosition: 745),
      ); // 12:25
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.textContaining('Resumes at 12:25'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders pause icon in trailing when track is active and playing',
        (tester) async {
      setSurfaceSize(tester, 400, 600);

      await tester.pumpWidget(
        buildTileHarness(track: testTrackLongTitle, isPlaying: true),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.byIcon(Icons.pause_circle_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
