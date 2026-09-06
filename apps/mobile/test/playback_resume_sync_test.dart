import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/controllers/audio_player_controller.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/services/audio_storage_service.dart';
import 'package:mobile/features/audio/services/audio_sync_service.dart';
import 'package:mobile/features/profile/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Cross-Session Playback Storage & Resume Tests', () {
    const testTrack = AudioTrack(
      id: 'genesis_part_1',
      title: 'Genesis - Part 1: Creation',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3600,
      audioUrl: 'https://example.com/audio/genesis1.mp3',
    );

    const testTrack2 = AudioTrack(
      id: 'genesis_part_2',
      title: 'Genesis - Part 2: The Fall',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3500,
      audioUrl: 'https://example.com/audio/genesis2.mp3',
    );

    test('AudioStorageService atomically saves and restores full playback state', () async {
      final storage = AudioStorageService();
      final now = DateTime.utc(2026, 9, 6, 12, 0, 0);

      await storage.savePlaybackState(
        track: testTrack,
        positionSeconds: 1245,
        queue: [testTrack, testTrack2],
        queueIndex: 0,
        updatedAt: now,
      );

      final state = await storage.getLastPlaybackState();
      expect(state, isNotNull);
      expect(state!.track.id, 'genesis_part_1');
      expect(state.track.title, 'Genesis - Part 1: Creation');
      expect(state.positionSeconds, 1245);
      expect(state.queue.length, 2);
      expect(state.queueIndex, 0);
      expect(state.updatedAt.toIso8601String(), now.toIso8601String());

      // Individual getters also return saved data
      final pos = await storage.getPosition(testTrack.id);
      expect(pos, 1245);

      final ts = await storage.getPositionUpdatedAt(testTrack.id);
      expect(ts, isNotNull);
      expect(ts!.toIso8601String(), now.toIso8601String());
    });

    test('AudioPlayerController initializes and restores last played session state', () async {
      final storage = AudioStorageService();
      await storage.savePlaybackState(
        track: testTrack,
        positionSeconds: 450,
        queue: [testTrack, testTrack2],
        queueIndex: 0,
      );

      // Create new controller instance simulating fresh app launch
      final controller = AudioPlayerController();
      // Allow async restore to finish
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.state.currentTrack, isNotNull);
      expect(controller.state.currentTrack!.id, testTrack.id);
      expect(controller.state.position.inSeconds, 450);
      expect(controller.state.duration.inSeconds, 3600);
      expect(controller.state.isMiniPlayerVisible, isTrue);
      expect(controller.state.queue.length, 2);

      controller.dispose();
    });

    test('UserService saves and retrieves video playback position', () async {
      final userService = UserService();

      // Video not yet played
      final initialPos = await userService.getVideoPosition('vid_123');
      expect(initialPos, 0);

      // Save playback position
      await userService.saveVideoPosition('vid_123', 789);

      final savedPos = await userService.getVideoPosition('vid_123');
      expect(savedPos, 789);
    });
  });

  group('Cross-Device AudioSyncService Tests', () {
    test('pullPlayback returns null safely when unauthenticated', () async {
      final syncService = AudioSyncService();
      final remote = await syncService.pullPlayback();
      expect(remote, isNull);
    });

    test('pushPlayback returns gracefully when unauthenticated', () async {
      final syncService = AudioSyncService();
      const track = AudioTrack(
        id: 'track_remote',
        title: 'Remote Test Track',
        seriesId: 'series_1',
        seriesTitle: 'Series 1',
        speaker: 'Speaker',
        durationSeconds: 1200,
        audioUrl: 'https://example.com/track.mp3',
      );

      // Should complete without throwing
      await syncService.pushPlayback(
        track: track,
        positionSeconds: 120,
        durationSeconds: 1200,
      );
    });
  });
}
