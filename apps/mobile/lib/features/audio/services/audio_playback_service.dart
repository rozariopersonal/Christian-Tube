import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audio_track.dart';

/// Wraps the underlying [AudioPlayer] engine and handles streaming,
/// local chunk caching, fallback URLs, and audio session events.
class AudioPlaybackService {
  final AudioPlayer _player;
  bool _isSessionConfigured = false;

  StreamSubscription? _becomingNoisySubscription;

  AudioPlaybackService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get speedStream => _player.speedStream;

  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  Duration get bufferedPosition => _player.bufferedPosition;
  bool get isPlaying => _player.playing;
  PlayerState get playerState => _player.playerState;
  ProcessingState get processingState => _player.processingState;

  /// Ensures native audio session is properly configured for speech/music background playback.
  Future<void> _ensureAudioSession() async {
    if (_isSessionConfigured || kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      _becomingNoisySubscription?.cancel();
      _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
        pause();
      });
      _isSessionConfigured = true;
    } catch (_) {
      // Ignored if unsupported on current test environment
    }
  }

  /// Loads and prepares an [AudioTrack] for streaming with local chunk caching.
  /// If the primary [audioUrl] fails, automatically attempts [fallbackUrl].
  Future<Duration?> loadTrack(AudioTrack track, {int initialPositionSec = 0}) async {
    await _ensureAudioSession();

    final initialPosition = initialPositionSec > 0
        ? Duration(seconds: initialPositionSec)
        : Duration.zero;

    // Headers to guarantee Cloudflare CDN byte-range and cache support
    final headers = {'User-Agent': 'ChristianTube/1.32'};

    try {
      // On non-web platforms, LockCachingAudioSource writes chunks to disk as they stream.
      // On web or environments where file cache is unavailable, standard AudioSource is used.
      AudioSource source;
      if (!kIsWeb) {
        // ignore: experimental_member_use
        source = LockCachingAudioSource(
          Uri.parse(track.audioUrl),
          headers: headers,
        );
      } else {
        source = AudioSource.uri(
          Uri.parse(track.audioUrl),
          headers: headers,
        );
      }

      final duration = await _player.setAudioSource(
        source,
        initialPosition: initialPosition,
      );
      return duration;
    } catch (e) {
      // Fallback URL retry
      if (track.fallbackUrl != null && track.fallbackUrl!.isNotEmpty) {
        try {
          AudioSource fallbackSource;
          if (!kIsWeb) {
            // ignore: experimental_member_use
            fallbackSource = LockCachingAudioSource(
              Uri.parse(track.fallbackUrl!),
              headers: headers,
            );
          } else {
            fallbackSource = AudioSource.uri(
              Uri.parse(track.fallbackUrl!),
              headers: headers,
            );
          }

          final duration = await _player.setAudioSource(
            fallbackSource,
            initialPosition: initialPosition,
          );
          return duration;
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> stop() => _player.stop();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> dispose() async {
    _becomingNoisySubscription?.cancel();
    await _player.dispose();
  }
}
