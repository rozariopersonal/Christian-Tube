import 'audio_track.dart';

enum AudioPlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  completed,
  error,
}

/// Single immutable snapshot of audio player behavioral state.
///
/// Follows the repository standard: views read this state directly and
/// deterministically without reaching into engine internals.
class AudioPlayerState {
  final AudioPlaybackStatus status;
  final AudioTrack? currentTrack;
  final List<AudioTrack> queue;
  final int queueIndex;

  // Timings
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;

  // Playback options
  final double speed;
  final bool isMiniPlayerVisible;
  final int? sleepTimerRemainingSeconds;
  final String? errorMessage;

  const AudioPlayerState({
    this.status = AudioPlaybackStatus.idle,
    this.currentTrack,
    this.queue = const [],
    this.queueIndex = -1,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.isMiniPlayerVisible = false,
    this.sleepTimerRemainingSeconds,
    this.errorMessage,
  });

  bool get isPlaying => status == AudioPlaybackStatus.playing;
  bool get isLoading => status == AudioPlaybackStatus.loading;
  bool get hasTrack => currentTrack != null;

  double get progress {
    if (duration.inMilliseconds <= 0) return 0.0;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    return ratio.clamp(0.0, 1.0);
  }

  AudioPlayerState copyWith({
    AudioPlaybackStatus? status,
    AudioTrack? currentTrack,
    bool clearCurrentTrack = false,
    List<AudioTrack>? queue,
    int? queueIndex,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    bool? isMiniPlayerVisible,
    int? sleepTimerRemainingSeconds,
    bool clearSleepTimer = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AudioPlayerState(
      status: status ?? this.status,
      currentTrack: clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      isMiniPlayerVisible: isMiniPlayerVisible ?? this.isMiniPlayerVisible,
      sleepTimerRemainingSeconds: clearSleepTimer
          ? null
          : (sleepTimerRemainingSeconds ?? this.sleepTimerRemainingSeconds),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
