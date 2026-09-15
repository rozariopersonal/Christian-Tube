import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mobile/features/audio/controllers/audio_player_controller.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/models/playback_state.dart';
import 'package:mobile/features/audio/services/audio_local_library.dart';
import 'package:mobile/features/audio/services/audio_playback_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

AudioTrack _track(
  String id, {
  String seriesId = 'series_a',
  String? audioUrl,
  String? streamUrl,
}) =>
    AudioTrack(
      id: id,
      title: 'Track $id',
      seriesId: seriesId,
      seriesTitle: 'Series',
      speaker: 'Zac Poonen',
      durationSeconds: 300,
      audioUrl: audioUrl ?? 'https://example.com/$id.mp3',
      streamUrl: streamUrl,
    );

/// Fake playback service that lets tests emit arbitrary player exceptions.
class _FakePlaybackService extends AudioPlaybackService {
  final StreamController<PlayerException> _errorController =
      StreamController<PlayerException>.broadcast();

  @override
  Stream<PlayerException> get errorStream => _errorController.stream;

  void emitError(PlayerException error) => _errorController.add(error);

  Future<void> close() => _errorController.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioPlayerController streaming error surfacing', () {
    test('async mid-stream error transitions state to error with message',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakePlaybackService();
      final controller = AudioPlayerController(playbackService: fake);

      final track = _track('t1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.setStateForTesting(AudioPlayerState(
        status: AudioPlaybackStatus.playing,
        currentTrack: track,
        queue: [track],
        queueIndex: 0,
      ));

      fake.emitError(PlayerException(403,
        'HTTP 403 Forbidden: access denied',
        0,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, AudioPlaybackStatus.error);
      expect(controller.state.errorMessage, contains('Access denied (403)'));

      controller.dispose();
      await fake.close();
    });

    test('webpage-instead-of-audio error maps to a readable message',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakePlaybackService();
      final controller = AudioPlayerController(playbackService: fake);

      final track = _track('t2');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.setStateForTesting(AudioPlayerState(
        status: AudioPlaybackStatus.playing,
        currentTrack: track,
        queue: [track],
        queueIndex: 0,
      ));

      fake.emitError(PlayerException(2,
        'Expected audio content but received text/html at '
            'https://audio.com/123456',
        1,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, AudioPlaybackStatus.error);
      expect(controller.state.errorMessage,
          contains('Received a webpage instead of audio'));

      controller.dispose();
      await fake.close();
    });

    test('errors are ignored while no track is active', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakePlaybackService();
      final controller = AudioPlayerController(playbackService: fake);

      fake.emitError(PlayerException(1, 'err', 2));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, isNot(AudioPlaybackStatus.error));

      controller.dispose();
      await fake.close();
    });

    test('errorMessageFrom classifies common failure modes', () {
      expect(
        AudioPlayerController.errorMessageFrom('HTTP 403 Forbidden'),
        contains('Access denied (403)'),
      );
      expect(
        AudioPlayerController.errorMessageFrom(
            'got text/html instead of a valid audio source'),
        contains('Received a webpage instead of audio'),
      );
      expect(
        AudioPlayerController.errorMessageFrom(
            'CORS request failed: cross-origin blocked'),
        contains('Blocked by CORS policy'),
      );
      expect(
        AudioPlayerController.errorMessageFrom(
            'Network error: connection timed out'),
        contains('Network error'),
      );
      expect(
        AudioPlayerController.errorMessageFrom('404 Not Found'),
        contains('Audio file not found (404)'),
      );
      expect(
        AudioPlayerController.errorMessageFrom('401 Unauthorized'),
        contains('Authentication required'),
      );
      expect(
        AudioPlayerController.errorMessageFrom('Something unexpected broke'),
        contains('Unable to stream audio'),
      );
    });
  });

  group('AudioTrack streamUrl round-trip', () {
    test('streamUrl survives toJson -> fromJson', () {
      final track = _track(
        'audio_com_1',
        seriesId: 'cfc',
        audioUrl: 'https://example.com/audio.mp3',
        streamUrl: 'https://s3.ustatik.com/signed/audio.mp3?sig=abc',
      );

      final restored = AudioTrack.fromJson(track.toJson());
      expect(restored.streamUrl, track.streamUrl);
    });

    test('audio.com page URLs resolve through the backend stream endpoint', () {
      final json = {
        'id': 'ac_1',
        'title': 'Song',
        'seriesId': 'cfc',
        'seriesTitle': 'CFC',
        'speaker': 'Choir',
        'durationSeconds': 180,
        'audioUrl': 'https://audio.com/1876018172771344',
      };

      final track = AudioTrack.fromJson(json);
      expect(track.streamUrl,
          'https://christianapp-zjdh.onrender.com/audio/stream/1876018172771344');
    });
  });

  group('AudioLocalLibrary extension resolution', () {
    late Directory tempDir;
    late AudioLocalLibrary library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('audio_stream_ext_test');
      library = AudioLocalLibrary(overrideBaseDir: () => tempDir);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('uses streamUrl extension when present', () async {
      final track = _track(
        'ext_stream',
        audioUrl: 'https://audio.com/123456',
        streamUrl: 'https://s3.ustatik.com/signed/track.m4a?sig=xyz',
      );
      final path = await library.pathFor(track);
      expect(p.basename(path), 'ext_stream.m4a');
    });

    test('falls back to audioUrl extension when streamUrl has none', () async {
      final track = _track(
        'ext_fallback',
        audioUrl: 'https://example.com/track.mp3',
        streamUrl: 'https://example.com/stream/podcast-show-24',
      );
      final path = await library.pathFor(track);
      expect(p.basename(path), 'ext_fallback.mp3');
    });

    test('defaults to mp3 when no URL carries an extension', () async {
      final track = _track(
        'ext_default',
        audioUrl: 'https://example.com/podcast',
      );
      final path = await library.pathFor(track);
      expect(p.basename(path), 'ext_default.mp3');
    });
  });
}