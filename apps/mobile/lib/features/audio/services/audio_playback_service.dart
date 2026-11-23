import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, visibleForTesting;
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
  StreamSubscription? _interruptionSubscription;
  bool _playOnInterruptionEnd = false;

  AudioPlaybackService({AudioPlayer? player, AudioLocalLibrary? localLibrary})
      : _player = player ?? AudioPlayer(),
        _localLibrary = localLibrary ?? AudioLocalLibrary();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get speedStream => _player.speedStream;
  Stream<PlayerException> get errorStream => _player.errorStream;

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
      _interruptionSubscription?.cancel();
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              setVolume(0.3);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              final wasPlaying = isPlaying;
              pause();
              _playOnInterruptionEnd = wasPlaying;
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              if (_playOnInterruptionEnd) {
                _playOnInterruptionEnd = false;
                play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
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

    final imageUrl = track.displayImageUrl;
    final mediaItem = MediaItem(
      id: track.id,
      album: track.speaker.isNotEmpty ? track.speaker : 'ChristianApp',
      title: track.title,
      artist: track.speaker,
      artUri: (imageUrl != null && imageUrl.isNotEmpty) ? Uri.tryParse(imageUrl) : null,
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

    try {
      // Prefer streamUrl (resolved direct audio file) over audioUrl (may be a landing page).
      final primaryUrl =
          track.streamUrl?.isNotEmpty == true ? track.streamUrl! : track.audioUrl;
      final source = buildStreamAudioSource(primaryUrl, tag: mediaItem);

      final duration = await _player.setAudioSource(
        source,
        initialPosition: initialPosition,
      );
      return duration;
    } catch (e) {
      // Fallback URL retry
      if (track.fallbackUrl != null && track.fallbackUrl!.isNotEmpty) {
        try {
          final fallbackSource =
              buildStreamAudioSource(track.fallbackUrl!, tag: mediaItem);

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

  static const Map<String, String> _nativeStreamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  /// Builds a streaming [UriAudioSource] for [rawUrl].
  ///
  /// On web (`just_audio_web`), custom HTTP headers (such as `User-Agent`)
  /// cannot be sent on `<audio>` elements and force an XHR/fetch fallback that
  /// fails with forbidden-header or CORS errors, so `headers` must be `null`.
  /// Also upgrades `http://` URLs to `https://` when served from an HTTPS
  /// origin to prevent mixed-content blocks.
  @visibleForTesting
  static UriAudioSource buildStreamAudioSource(
    String rawUrl, {
    MediaItem? tag,
    bool isWeb = kIsWeb,
    bool? isHttpsOrigin,
  }) {
    var uri = Uri.parse(rawUrl);
    final httpsPage = isHttpsOrigin ?? (isWeb && Uri.base.scheme == 'https');
    if (isWeb && httpsPage && uri.scheme == 'http') {
      uri = uri.replace(scheme: 'https');
    }
    return AudioSource.uri(
      uri,
      headers: isWeb ? null : _nativeStreamHeaders,
      tag: tag,
    );
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> stop() => _player.stop();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> dispose() async {
    _becomingNoisySubscription?.cancel();
    _interruptionSubscription?.cancel();
    await _player.dispose();
  }
}
