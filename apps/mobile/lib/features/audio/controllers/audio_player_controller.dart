import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audio_track.dart';
import '../models/playback_state.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_storage_service.dart';
import '../services/audio_sync_service.dart';

/// Top-level audio player controller adhering to the project's Architecture Standard:
/// - Single derived immutable state broadcast via [ChangeNotifier].
/// - Consumers read [controller.state.field], never scattered internals.
class AudioPlayerController extends ChangeNotifier {
  static final AudioPlayerController instance = AudioPlayerController();

  final AudioPlaybackService _playbackService;
  final AudioStorageService _storageService;
  final AudioSyncService _syncService;

  AudioPlayerState _state = const AudioPlayerState();
  AudioPlayerState get state => _state;

  @visibleForTesting
  void setStateForTesting(AudioPlayerState newState) {
    _state = newState;
    notifyListeners();
  }

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<double>? _speedSub;

  Timer? _positionSaveDebounce;
  Timer? _sleepTimer;

  AudioPlayerController({
    AudioPlaybackService? playbackService,
    AudioStorageService? storageService,
    AudioSyncService? syncService,
  })  : _playbackService = playbackService ?? AudioPlaybackService(),
        _storageService = storageService ?? AudioStorageService(),
        _syncService = syncService ?? AudioSyncService.instance {
    _initStreams();
    _restoreLastPlayedTrack();
  }

  void _initStreams() {
    _posSub = _playbackService.positionStream.listen((pos) {
      if (_playbackService.processingState == ProcessingState.idle &&
          _state.currentTrack != null &&
          _state.position > Duration.zero &&
          pos == Duration.zero) {
        // Guard: Do not let an uninitialized/idle player position stream wipe out restored playhead
        return;
      }
      _state = _state.copyWith(position: pos);
      notifyListeners();
      _schedulePositionSave();
    });

    _durSub = _playbackService.durationStream.listen((dur) {
      if (dur != null) {
        _state = _state.copyWith(duration: dur);
        notifyListeners();
      }
    });

    _bufSub = _playbackService.bufferedPositionStream.listen((buf) {
      _state = _state.copyWith(bufferedPosition: buf);
      notifyListeners();
    });

    _speedSub = _playbackService.speedStream.listen((spd) {
      _state = _state.copyWith(speed: spd);
      notifyListeners();
    });

    _stateSub = _playbackService.playerStateStream.listen((ps) {
      AudioPlaybackStatus newStatus = _state.status;
      if (ps.processingState == ProcessingState.loading ||
          ps.processingState == ProcessingState.buffering) {
        newStatus = AudioPlaybackStatus.loading;
      } else if (ps.processingState == ProcessingState.completed) {
        newStatus = AudioPlaybackStatus.completed;
        _onTrackCompleted();
      } else if (ps.playing) {
        newStatus = AudioPlaybackStatus.playing;
      } else {
        newStatus = AudioPlaybackStatus.paused;
      }

      if (newStatus != _state.status) {
        _state = _state.copyWith(status: newStatus);
        notifyListeners();
      }
    });
  }

  /// Restores session state from local storage immediately, then asynchronously checks
  /// if cloud has a newer timestamp from another device.
  Future<void> _restoreLastPlayedTrack() async {
    final stored = await _storageService.getLastPlaybackState();
    if (stored != null && _state.currentTrack == null) {
      _state = _state.copyWith(
        currentTrack: stored.track,
        position: Duration(seconds: stored.positionSeconds),
        duration: Duration(seconds: stored.track.durationSeconds),
        queue: stored.queue,
        queueIndex: stored.queueIndex,
        isMiniPlayerVisible: true, // Visible & docked on startup for 1-tap resume
      );
      notifyListeners();
    }

    // Check cloud synchronization in background across devices
    _pullRemotePlayback(localUpdatedAt: stored?.updatedAt);
  }

  /// Checks the backend for newer playback progress from another device.
  Future<void> _pullRemotePlayback({DateTime? localUpdatedAt}) async {
    try {
      final remote = await _syncService.pullPlayback();
      if (remote == null) return;

      // Only update if remote state is newer than our local state,
      // and we are not currently playing a different track.
      final shouldUpdate = localUpdatedAt == null ||
          remote.updatedAt.isAfter(localUpdatedAt);

      if (shouldUpdate && !_state.isPlaying) {
        await _storageService.savePlaybackState(
          track: remote.track,
          positionSeconds: remote.positionSeconds,
          updatedAt: remote.updatedAt,
        );

        _state = _state.copyWith(
          currentTrack: remote.track,
          position: Duration(seconds: remote.positionSeconds),
          duration: Duration(seconds: remote.durationSeconds),
          isMiniPlayerVisible: true,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AudioPlayerController pullRemotePlayback non-blocking error: $e');
    }
  }

  /// Manually triggers a pull from the cloud (e.g. when opening the Audio Library screen or signing in).
  Future<void> syncWithCloud() async {
    final localUpdatedAt = await _storageService.getLastTrackUpdatedAt();
    await _pullRemotePlayback(localUpdatedAt: localUpdatedAt);
  }

  /// Plays the given [track], optionally with a surrounding [queue].
  Future<void> playTrack(
    AudioTrack track, {
    List<AudioTrack>? queue,
    int? resumePositionSec,
  }) async {
    final effectiveQueue = queue ?? [track];
    final queueIdx = effectiveQueue.indexWhere((t) => t.id == track.id);

    // Check if we have a saved resume position
    int startPos = resumePositionSec ?? 0;
    if (startPos == 0) {
      startPos = await _storageService.getPosition(track.id);
      // If position is near the end, start from beginning
      if (startPos >= track.durationSeconds - 5) startPos = 0;
    }

    _state = _state.copyWith(
      status: AudioPlaybackStatus.loading,
      currentTrack: track,
      queue: effectiveQueue,
      queueIndex: queueIdx >= 0 ? queueIdx : 0,
      position: Duration(seconds: startPos),
      duration: Duration(seconds: track.durationSeconds),
      isMiniPlayerVisible: true,
      clearError: true,
    );
    notifyListeners();

    try {
      final dur = await _playbackService.loadTrack(
        track,
        initialPositionSec: startPos,
      );
      if (dur != null) {
        _state = _state.copyWith(duration: dur);
      }
      await _playbackService.play();

      final now = DateTime.now().toUtc();
      await _storageService.savePlaybackState(
        track: track,
        positionSeconds: startPos,
        queue: effectiveQueue,
        queueIndex: queueIdx >= 0 ? queueIdx : 0,
        updatedAt: now,
      );
      _syncService.pushPlayback(
        track: track,
        positionSeconds: startPos,
        durationSeconds: track.durationSeconds,
        force: true,
        updatedAt: now,
      );
    } catch (e) {
      _state = _state.copyWith(
        status: AudioPlaybackStatus.error,
        errorMessage: 'Unable to stream audio. Please check your connection.',
      );
      notifyListeners();
    }
  }

  /// Toggles between play and pause.
  /// Correctly handles restored session tracks where just_audio has not loaded the source yet.
  Future<void> togglePlayPause() async {
    if (_state.isPlaying) {
      await _playbackService.pause();
      await flushPlayback();
    } else {
      if (_state.currentTrack != null) {
        if (_state.status == AudioPlaybackStatus.completed) {
          await seek(Duration.zero);
          await _playbackService.play();
        } else if (_playbackService.playerState.processingState == ProcessingState.idle) {
          // Fresh session launch: the audio source is not yet loaded into just_audio!
          await playTrack(
            _state.currentTrack!,
            queue: _state.queue.isNotEmpty ? _state.queue : [_state.currentTrack!],
            resumePositionSec: _state.position.inSeconds,
          );
        } else {
          await _playbackService.play();
        }
      }
    }
  }

  /// Jumps to a specific duration.
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position);
    notifyListeners();
    await _playbackService.seek(position);
    await flushPlayback();
  }

  /// Immediately flushes the current playhead position to local disk and cloud.
  /// Call this when pausing, seeking, or when the app lifecycle changes (background/exit).
  Future<void> flushPlayback() async {
    final track = _state.currentTrack;
    if (track == null) return;

    final pos = _state.position.inSeconds;
    final now = DateTime.now().toUtc();

    await _storageService.savePlaybackState(
      track: track,
      positionSeconds: pos,
      queue: _state.queue,
      queueIndex: _state.queueIndex,
      updatedAt: now,
    );

    _syncService.pushPlayback(
      track: track,
      positionSeconds: pos,
      durationSeconds: track.durationSeconds,
      force: true,
      updatedAt: now,
    );
  }

  /// Jumps forward or backward by [secondsDelta] (e.g. -10 or +30).
  Future<void> seekRelative(int secondsDelta) async {
    final targetMs =
        (_state.position.inMilliseconds + (secondsDelta * 1000)).clamp(
      0,
      _state.duration.inMilliseconds,
    );
    await seek(Duration(milliseconds: targetMs));
  }

  /// Cycles between common playback speeds: 1.0 -> 1.2 -> 1.5 -> 2.0 -> 0.8 -> 1.0
  Future<void> cyclePlaybackSpeed() async {
    final current = _state.speed;
    double nextSpeed;
    if (current == 1.0) {
      nextSpeed = 1.2;
    } else if (current == 1.2) {
      nextSpeed = 1.5;
    } else if (current == 1.5) {
      nextSpeed = 2.0;
    } else if (current == 2.0) {
      nextSpeed = 0.8;
    } else {
      nextSpeed = 1.0;
    }
    await setPlaybackSpeed(nextSpeed);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _state = _state.copyWith(speed: speed);
    notifyListeners();
    await _playbackService.setSpeed(speed);
  }

  /// Sets a sleep timer in minutes (e.g. 15, 30, 45, 60, or null to cancel).
  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    if (minutes == null || minutes <= 0) {
      _state = _state.copyWith(clearSleepTimer: true);
      notifyListeners();
      return;
    }

    int remainingSeconds = minutes * 60;
    _state = _state.copyWith(sleepTimerRemainingSeconds: remainingSeconds);
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remainingSeconds--;
      if (remainingSeconds <= 0) {
        timer.cancel();
        _state = _state.copyWith(clearSleepTimer: true);
        notifyListeners();
        _playbackService.pause();
      } else {
        _state = _state.copyWith(sleepTimerRemainingSeconds: remainingSeconds);
        notifyListeners();
      }
    });
  }

  /// Advances to next track in queue.
  Future<void> skipNext() async {
    if (_state.queue.isEmpty) return;
    final nextIdx = _state.queueIndex + 1;
    if (nextIdx < _state.queue.length) {
      await playTrack(
        _state.queue[nextIdx],
        queue: _state.queue,
      );
    }
  }

  /// Goes to previous track in queue or restarts current track.
  Future<void> skipPrevious() async {
    if (_state.position.inSeconds > 5) {
      await seek(Duration.zero);
      return;
    }
    final prevIdx = _state.queueIndex - 1;
    if (prevIdx >= 0 && prevIdx < _state.queue.length) {
      await playTrack(
        _state.queue[prevIdx],
        queue: _state.queue,
      );
    }
  }

  void dismissMiniPlayer() {
    _state = _state.copyWith(isMiniPlayerVisible: false);
    notifyListeners();
  }

  void _onTrackCompleted() {
    // If there's an active sleep timer set to 'End of Track', pause
    if (_state.sleepTimerRemainingSeconds != null &&
        _state.sleepTimerRemainingSeconds == 0) {
      return;
    }
    // Auto-advance to next track in queue
    skipNext();
  }

  void _schedulePositionSave() {
    _positionSaveDebounce?.cancel();
    _positionSaveDebounce = Timer(const Duration(seconds: 3), () {
      final track = _state.currentTrack;
      if (track != null) {
        final pos = _state.position.inSeconds;
        _storageService.savePosition(track.id, pos);
        _syncService.pushPlayback(
          track: track,
          positionSeconds: pos,
          durationSeconds: track.durationSeconds,
        );
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _bufSub?.cancel();
    _stateSub?.cancel();
    _speedSub?.cancel();
    _positionSaveDebounce?.cancel();
    _sleepTimer?.cancel();
    _playbackService.dispose();
    super.dispose();
  }
}
