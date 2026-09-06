import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/audio_track.dart';

/// Wraps the underlying [AudioPlayer] engine and handles streaming,
/// fallback URLs, and audio session events.
class AudioPlaybackService {
  final AudioPlayer _player;

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

  /// Loads and prepares an [AudioTrack] for playback.
  /// If the primary [audioUrl] fails, automatically attempts [fallbackUrl].
  Future<Duration?> loadTrack(AudioTrack track, {int initialPositionSec = 0}) async {
    try {
      final initialPosition = initialPositionSec > 0
          ? Duration(seconds: initialPositionSec)
          : Duration.zero;

      final duration = await _player.setUrl(
        track.audioUrl,
        initialPosition: initialPosition,
      );
      return duration;
    } catch (e) {
      if (track.fallbackUrl != null && track.fallbackUrl!.isNotEmpty) {
        final initialPosition = initialPositionSec > 0
            ? Duration(seconds: initialPositionSec)
            : Duration.zero;

        final duration = await _player.setUrl(
          track.fallbackUrl!,
          initialPosition: initialPosition,
        );
        return duration;
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

  Future<void> dispose() => _player.dispose();
}
