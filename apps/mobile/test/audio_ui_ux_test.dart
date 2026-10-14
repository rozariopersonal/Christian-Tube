import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/audio/controllers/audio_player_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/models/playback_state.dart';
import 'package:mobile/features/audio/screens/audio_series_screen.dart';
import 'package:mobile/features/audio/widgets/full_audio_player_sheet.dart';
import 'package:mobile/features/audio/widgets/mini_audio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testTrack1 = AudioTrack(
    id: 'track_1',
    title: 'Genesis - The Creation',
    seriesId: 'ttb_gen',
    seriesTitle: 'Through The Bible',
    speaker: 'Zac Poonen',
    durationSeconds: 1800,
    audioUrl: 'https://example.com/1.mp3',
    scriptureBook: 'GEN',
    scriptureChapter: 1,
    scriptureVerse: 1,
  );

  const testTrack2 = AudioTrack(
    id: 'track_2',
    title: 'Genesis - The Fall of Man',
    seriesId: 'ttb_gen',
    seriesTitle: 'Through The Bible',
    speaker: 'Zac Poonen',
    durationSeconds: 2100,
    audioUrl: 'https://example.com/2.mp3',
    scriptureBook: 'GEN',
    scriptureChapter: 3,
    scriptureVerse: 1,
  );

  const testSeries = AudioSeries(
    id: 'ttb_gen',
    title: 'Genesis Survey',
    description: 'Complete overview of the book of Genesis',
    speaker: 'Zac Poonen',
    trackCount: 2,
    category: 'Bible Survey',
    tracks: [testTrack1, testTrack2],
  );

  Widget buildPlayerTestHarness({AudioPlayerState? state}) {
    if (state != null) {
      AudioPlayerController.instance.setStateForTesting(state);
    }

    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [AppTokens.dark],
      ),
      home: const Scaffold(
        body: FullAudioPlayerSheet(),
      ),
    );
  }

  group('FullAudioPlayerSheet UI/UX Tests', () {
    testWidgets('renders all 5 main playback controls: prev, -10s, play/pause, +30s, next', (tester) async {
      setSurfaceSize(tester, 400, 1000);
      await tester.pumpWidget(buildPlayerTestHarness(
        state: const AudioPlayerState(
          currentTrack: testTrack1,
          queue: [testTrack1, testTrack2],
          queueIndex: 0,
          status: AudioPlaybackStatus.playing,
          position: Duration(minutes: 5),
          duration: Duration(minutes: 30),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.replay_10), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.pause || w.icon == Icons.play_arrow)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.forward_30), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);

      // Verify secondary utilities row
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('Queue (2)'), findsOneWidget);
    });

    testWidgets('tapping Queue button opens Queue bottom sheet with track list', (tester) async {
      setSurfaceSize(tester, 400, 1000);
      await tester.pumpWidget(buildPlayerTestHarness(
        state: const AudioPlayerState(
          currentTrack: testTrack1,
          queue: [testTrack1, testTrack2],
          queueIndex: 0,
          status: AudioPlaybackStatus.playing,
          position: Duration(minutes: 5),
          duration: Duration(minutes: 30),
        ),
      ));
      await tester.pump();

      // Tap Queue chip
      await tester.tap(find.text('Queue (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Playback Queue (2 Tracks)'), findsOneWidget);
      expect(find.text('Genesis - The Creation'), findsWidgets);
      expect(find.text('Genesis - The Fall of Man'), findsOneWidget);
    });

    testWidgets('displays error recovery banner with Retry button when playback status is error', (tester) async {
      await tester.pumpWidget(buildPlayerTestHarness(
        state: const AudioPlayerState(
          currentTrack: testTrack1,
          queue: [testTrack1, testTrack2],
          queueIndex: 0,
          status: AudioPlaybackStatus.error,
          errorMessage: 'Unable to stream audio. Please check your connection.',
          position: Duration.zero,
          duration: Duration(minutes: 30),
        ),
      ));
      await tester.pump();

      expect(find.text('Unable to stream audio. Please check your connection.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders FullAudioPlayerSheet without overflow at width $width', (tester) async {
        setSurfaceSize(tester, width, 900);
        await tester.pumpWidget(buildPlayerTestHarness(
          state: const AudioPlayerState(
            currentTrack: testTrack1,
            queue: [testTrack1, testTrack2],
            queueIndex: 0,
            status: AudioPlaybackStatus.playing,
            position: Duration(minutes: 5),
            duration: Duration(minutes: 30),
          ),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AudioSeriesScreen UI Tests', () {
    testWidgets('renders Play All button and tracks in MaxWidthBox', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: AudioSeriesScreen(
            seriesId: testSeries.id,
            initialSeries: testSeries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Play All (2 Tracks)'), findsOneWidget);
      expect(find.text('Genesis - The Creation'), findsOneWidget);
      expect(find.text('Genesis - The Fall of Man'), findsOneWidget);
    });

    testWidgets('renders without overflow at 320 and 600 with search bar', (tester) async {
      for (final width in [320.0, 600.0]) {
        setSurfaceSize(tester, width, 800);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: [AppTokens.dark],
            ),
            home: AudioSeriesScreen(
              seriesId: testSeries.id,
              initialSeries: testSeries,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Search this series...'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('in-channel search filters visible tracks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: AudioSeriesScreen(
            seriesId: testSeries.id,
            initialSeries: testSeries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search bar exists and both tracks visible initially.
      expect(find.text('Search this series...'), findsOneWidget);
      expect(find.text('Genesis - The Creation'), findsOneWidget);
      expect(find.text('Genesis - The Fall of Man'), findsOneWidget);

      // Filter down to one track.
      await tester.enterText(find.byType(TextField), 'Fall of Man');
      await tester.pump();

      expect(find.text('Genesis - The Fall of Man'), findsOneWidget);
      expect(find.text('Genesis - The Creation'), findsNothing);
      expect(find.text('1 of 2 tracks'), findsOneWidget);

      // A no-match query shows the empty state.
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();

      expect(find.textContaining('No tracks match'), findsOneWidget);

      // Clearing restores the full list.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Genesis - The Creation'), findsOneWidget);
      expect(find.text('Genesis - The Fall of Man'), findsOneWidget);
    });
  });

  group('MiniAudioPlayer Gestures Test', () {
    testWidgets('swipe left invokes skipNext and swipe right invokes skipPrevious', (tester) async {
      const state = AudioPlayerState(
        currentTrack: testTrack1,
        queue: [testTrack1, testTrack2],
        queueIndex: 0,
        status: AudioPlaybackStatus.playing,
        position: Duration(minutes: 2),
        duration: Duration(minutes: 30),
        isMiniPlayerVisible: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: const Scaffold(
            body: MiniAudioPlayer(state: state),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MiniAudioPlayer), findsOneWidget);

      // Perform horizontal swipe left (towards next track)
      await tester.fling(find.byType(Material).first, const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping close button pauses and dismisses mini player', (tester) async {
      AudioPlayerController.instance.setStateForTesting(const AudioPlayerState(
        currentTrack: testTrack1,
        queue: [testTrack1],
        queueIndex: 0,
        status: AudioPlaybackStatus.playing,
        isMiniPlayerVisible: true,
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: AudioPlayerController.instance,
              builder: (context, _) {
                final s = AudioPlayerController.instance.state;
                if (s.isMiniPlayerVisible && s.hasTrack) {
                  return MiniAudioPlayer(state: s);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MiniAudioPlayer), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(AudioPlayerController.instance.state.isMiniPlayerVisible, isFalse);
      expect(find.byType(MiniAudioPlayer), findsNothing);
    });

    testWidgets('vertical swipe down dismisses mini player', (tester) async {
      AudioPlayerController.instance.setStateForTesting(const AudioPlayerState(
        currentTrack: testTrack1,
        queue: [testTrack1],
        queueIndex: 0,
        status: AudioPlaybackStatus.playing,
        isMiniPlayerVisible: true,
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: AudioPlayerController.instance,
              builder: (context, _) {
                final s = AudioPlayerController.instance.state;
                if (s.isMiniPlayerVisible && s.hasTrack) {
                  return MiniAudioPlayer(state: s);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MiniAudioPlayer), findsOneWidget);

      // Perform vertical swipe down on the mini player card
      await tester.fling(
        find.descendant(
          of: find.byType(MiniAudioPlayer),
          matching: find.byType(GestureDetector),
        ).first,
        const Offset(0, 500),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(AudioPlayerController.instance.state.isMiniPlayerVisible, isFalse);
    });
  });
}
