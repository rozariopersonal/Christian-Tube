import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/audio_track.dart';
import 'audio_local_library.dart';

/// Wraps the underlying [AudioPlayer] engine and handles streaming,
/// local chunk caching, fallback URLs, and audio session events.
class AudioPlaybackService {
  final AudioPlayer _player;
  bool _isSessionConfigured = false;
  final AudioLocalLibrary _localLibrary;

  StreamSubscription? _becomingNoisySubscription;

  AudioPlaybackService({AudioPlayer? player, AudioLocalLibrary? localLibrary})
      : _player = player ?? AudioPlayer(),
        _localLibrary = localLibrary ?? AudioLocalLibrary();

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
  /// If the track has been downloaded for offline use, the local file is played
  /// instead of the remote stream. Otherwise the primary [audioUrl] is used, with
  /// automatic fallback to [fallbackUrl] on failure.
  Future<Duration?> loadTrack(AudioTrack track, {int initialPositionSec = 0}) async {
    await _ensureAudioSession();

    final initialPosition = initialPositionSec > 0
        ? Duration(seconds: initialPositionSec)
        : Duration.zero;

    final mediaItem = MediaItem(
      id: track.id,
      album: track.speaker.isNotEmpty ? track.speaker : 'ChristianTube',
      title: track.title,
      artist: track.speaker,
      artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      extras: {'youtubeVideoId': track.youtubeVideoId},
    );

    // Offline: prefer the locally downloaded file when present.
    final localUri = await _localLibrary.localUriFor(track);
    if (localUri != null) {
      try {
        return await _player.setAudioSource(
          AudioSource.uri(Uri.parse(localUri), tag: mediaItem),
          initialPosition: initialPosition,
        );
      } catch (e) {
        debugPrint('Local audio load failed, falling back to stream: $e');
      }
    }

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
          tag: mediaItem,
        );
      } else {
        source = AudioSource.uri(
          Uri.parse(track.audioUrl),
          headers: headers,
          tag: mediaItem,
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
