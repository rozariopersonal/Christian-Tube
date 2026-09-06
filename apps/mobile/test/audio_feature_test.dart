import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/audio/controllers/audio_player_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/models/playback_state.dart';
import 'package:mobile/features/audio/services/audio_catalog_service.dart';
import 'package:mobile/features/audio/widgets/mini_audio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('Audio Models & State Tests', () {
    test('AudioTrack parses JSON and formats duration correctly', () {
      const track = AudioTrack(
        id: 'track_1',
        title: 'Genesis 1',
        seriesId: 'ttb',
        seriesTitle: 'Through The Bible',
        speaker: 'Zac Poonen',
        durationSeconds: 3665,
        audioUrl: 'https://example.com/audio.mp3',
        scriptureBook: 'GEN',
        scriptureChapter: 1,
        scriptureVerse: 1,
      );

      expect(track.formattedDuration, '61:05');
      expect(track.hasScripture, isTrue);
      expect(track.scriptureRefText, 'GEN 1:1');

      final json = track.toJson();
      final fromJson = AudioTrack.fromJson(json);
      expect(fromJson.id, track.id);
      expect(fromJson.title, track.title);
      expect(fromJson.durationSeconds, track.durationSeconds);
      expect(fromJson.scriptureBook, 'GEN');
    });

    test('AudioSeries parses JSON with tracks list', () {
      final json = {
        'id': 'ttb',
        'title': 'Through The Bible',
        'description': 'Bible survey',
        'speaker': 'Zac Poonen',
        'trackCount': 1,
        'category': 'Bible Survey',
        'tracks': [
          {
            'id': 't1',
            'title': 'Part 1',
            'seriesId': 'ttb',
            'seriesTitle': 'Through The Bible',
            'speaker': 'Zac Poonen',
            'durationSeconds': 1800,
            'audioUrl': 'https://example.com/1.mp3',
          }
        ]
      };

      final series = AudioSeries.fromJson(json);
      expect(series.id, 'ttb');
      expect(series.tracks.length, 1);
      expect(series.tracks.first.title, 'Part 1');
    });

    test('AudioPlayerState progress calculation clamps properly', () {
      const stateZero = AudioPlayerState();
      expect(stateZero.progress, 0.0);

      const stateHalf = AudioPlayerState(
        duration: Duration(seconds: 100),
        position: Duration(seconds: 50),
      );
      expect(stateHalf.progress, 0.5);

      const stateOver = AudioPlayerState(
        duration: Duration(seconds: 100),
        position: Duration(seconds: 150),
      );
      expect(stateOver.progress, 1.0);
    });
  });

  group('AudioCatalogService Tests', () {
    test('Returns seed catalog when remote fetch fails or offline', () async {
      final service = AudioCatalogService();
      final catalog = await service.getCatalog();
      expect(catalog.isNotEmpty, isTrue);
      expect(catalog.any((s) => s.id == 'through_the_bible'), isTrue);

      final ttb = await service.getSeries('through_the_bible');
      expect(ttb, isNotNull);
      expect(ttb!.tracks.isNotEmpty, isTrue);
    });
  });

  group('AudioPlayerController Logic Tests', () {
    test('cyclePlaybackSpeed cycles correctly: 1.0 -> 1.2 -> 1.5 -> 2.0 -> 0.8 -> 1.0', () async {
      final controller = AudioPlayerController();

      expect(controller.state.speed, 1.0);
      await controller.cyclePlaybackSpeed();
      expect(controller.state.speed, 1.2);
      await controller.cyclePlaybackSpeed();
      expect(controller.state.speed, 1.5);
      await controller.cyclePlaybackSpeed();
      expect(controller.state.speed, 2.0);
      await controller.cyclePlaybackSpeed();
      expect(controller.state.speed, 0.8);
      await controller.cyclePlaybackSpeed();
      expect(controller.state.speed, 1.0);
    });

    test('setSleepTimer updates state and clears properly', () {
      final controller = AudioPlayerController();

      controller.setSleepTimer(15);
      expect(controller.state.sleepTimerRemainingSeconds, 15 * 60);

      controller.setSleepTimer(null);
      expect(controller.state.sleepTimerRemainingSeconds, isNull);
    });
  });

  group('MiniAudioPlayer Widget Tests', () {
    testWidgets('Renders properly without overflow at 320px width', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const track = AudioTrack(
        id: 'track_test',
        title: 'Genesis - Part 1: The Creation',
        seriesId: 'ttb',
        seriesTitle: 'Through The Bible',
        speaker: 'Zac Poonen',
        durationSeconds: 3000,
        audioUrl: 'https://example.com/test.mp3',
      );

      const state = AudioPlayerState(
        currentTrack: track,
        status: AudioPlaybackStatus.playing,
        position: Duration(minutes: 10),
        duration: Duration(minutes: 50),
        isMiniPlayerVisible: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AppTokens.dark],
          ),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MiniAudioPlayer(state: state),
            ),
          ),
        ),
      );

      expect(find.text('Genesis - Part 1: The Creation'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders properly at tablet 840px width', (tester) async {
      tester.view.physicalSize = const Size(840, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const track = AudioTrack(
        id: 'track_test',
        title: 'Genesis - Part 1: The Creation',
        seriesId: 'ttb',
        seriesTitle: 'Through The Bible',
        speaker: 'Zac Poonen',
        durationSeconds: 3000,
        audioUrl: 'https://example.com/test.mp3',
      );

      const state = AudioPlayerState(
        currentTrack: track,
        status: AudioPlaybackStatus.paused,
        position: Duration(minutes: 10),
        duration: Duration(minutes: 50),
        isMiniPlayerVisible: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [AppTokens.light],
          ),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MiniAudioPlayer(state: state),
            ),
          ),
        ),
      );

      expect(find.text('Genesis - Part 1: The Creation'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
