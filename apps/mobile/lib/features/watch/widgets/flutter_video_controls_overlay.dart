import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// A rich, ultra-smooth Flutter-native video player control overlay.
/// Replaces YouTube webview/iframe native controls with a clean, branded Christian-Tube UI.
class FlutterVideoControlsOverlay extends StatefulWidget {
  final YoutubePlayerController? controller;

  // Generic / Web callback support:
  final bool? isPlaying;
  final bool? isBuffering;
  final Duration? position;
  final Duration? duration;
  final double? playbackRate;
  final bool isFullScreen;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<double>? onSetSpeed;
  final VoidCallback? onToggleFullScreen;

  const FlutterVideoControlsOverlay({
    super.key,
    this.controller,
    this.isPlaying,
    this.isBuffering,
    this.position,
    this.duration,
    this.playbackRate,
    this.isFullScreen = false,
    this.onPlay,
    this.onPause,
    this.onSeek,
    this.onSetSpeed,
    this.onToggleFullScreen,
  });

  @override
  State<FlutterVideoControlsOverlay> createState() =>
      _FlutterVideoControlsOverlayState();
}

class _FlutterVideoControlsOverlayState
    extends State<FlutterVideoControlsOverlay>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isScrubbing = false;
  double _scrubValue = 0.0;

  // Double-tap seek visual feedback
  bool _isRewindActive = false;
  bool _isForwardActive = false;
  Timer? _rewindFeedbackTimer;
  Timer? _forwardFeedbackTimer;

  // Playback speeds
  static const List<double> _availableSpeeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerUpdate);
    _startHideTimer();
  }

  @override
  void didUpdateWidget(covariant FlutterVideoControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _rewindFeedbackTimer?.cancel();
    _forwardFeedbackTimer?.cancel();
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isPlaying {
    if (widget.controller != null) {
      return widget.controller!.value.isPlaying;
    }
    return widget.isPlaying ?? false;
  }

  bool get _isBuffering {
    if (widget.controller != null) {
      return widget.controller!.value.playerState == PlayerState.buffering;
    }
    return widget.isBuffering ?? false;
  }

  bool get _isEnded {
    if (widget.controller != null) {
      return widget.controller!.value.playerState == PlayerState.ended;
    }
    return false;
  }

  Duration get _currentPosition {
    if (_isScrubbing) {
      return Duration(milliseconds: _scrubValue.toInt());
    }
    if (widget.controller != null) {
      return widget.controller!.value.position;
    }
    return widget.position ?? Duration.zero;
  }

  Duration get _totalDuration {
    if (widget.controller != null) {
      final d = widget.controller!.metadata.duration;
      return d.inMilliseconds > 0 ? d : const Duration(seconds: 1);
    }
    return widget.duration != null && widget.duration!.inMilliseconds > 0
        ? widget.duration!
        : const Duration(seconds: 1);
  }

  double get _playbackRate {
    if (widget.controller != null) {
      return widget.controller!.value.playbackRate;
    }
    return widget.playbackRate ?? 1.0;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isScrubbing && _isPlaying) {
      _hideTimer = Timer(const Duration(milliseconds: 3200), () {
        if (mounted && _isPlaying && !_isScrubbing) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControlsVisibility() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    HapticFeedback.lightImpact();
    if (widget.controller != null) {
      if (_isPlaying) {
        widget.controller!.pause();
      } else {
        if (_isEnded) {
          widget.controller!.seekTo(Duration.zero);
        }
        widget.controller!.play();
      }
    } else {
      if (_isPlaying) {
        widget.onPause?.call();
      } else {
        widget.onPlay?.call();
      }
    }
    _startHideTimer();
    setState(() {});
  }

  void _seekBy(int seconds) {
    HapticFeedback.selectionClick();
    final newPos = _currentPosition + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, _totalDuration.inMilliseconds),
    );

    if (widget.controller != null) {
      widget.controller!.seekTo(clamped);
    } else {
      widget.onSeek?.call(clamped);
    }
    _startHideTimer();
  }

  void _triggerDoubleTapRewind() {
    _seekBy(-10);
    setState(() {
      _isRewindActive = true;
      _showControls = true;
    });
    _rewindFeedbackTimer?.cancel();
    _rewindFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _isRewindActive = false);
    });
    _startHideTimer();
  }

  void _triggerDoubleTapForward() {
    _seekBy(10);
    setState(() {
      _isForwardActive = true;
      _showControls = true;
    });
    _forwardFeedbackTimer?.cancel();
    _forwardFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _isForwardActive = false);
    });
    _startHideTimer();
  }

  void _onSpeedSelected(double speed) {
    if (widget.controller != null) {
      widget.controller!.setPlaybackRate(speed);
    } else {
      widget.onSetSpeed?.call(speed);
    }
    _startHideTimer();
    setState(() {});
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final zoneWidth = width * 0.38;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Tap to toggle controls background detector
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControlsVisibility,
              child: const SizedBox.expand(),
            ),

            // Left Side: Double-Tap Rewind Zone
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: zoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _triggerDoubleTapRewind,
                child: AnimatedOpacity(
                  opacity: _isRewindActive ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(100),
                      ),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay_10_rounded, color: Colors.white, size: 36),
                          SizedBox(height: 4),
                          Text(
                            '-10s',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Right Side: Double-Tap Fast-Forward Zone
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: zoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _triggerDoubleTapForward,
                child: AnimatedOpacity(
                  opacity: _isForwardActive ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(100),
                      ),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forward_10_rounded, color: Colors.white, size: 36),
                          SizedBox(height: 4),
                          Text(
                            '+10s',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Main Animated Control HUD Overlay
            IgnorePointer(
              ignoring: !_showControls,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.42),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar (Empty space or gradient scrim)
                      const SizedBox(height: 20),

                      // Center Playback Buttons: [-10s] [Play/Pause/Buffer] [+10s]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // -10s Button
                          _buildCircleButton(
                            icon: Icons.replay_10_rounded,
                            size: 24,
                            buttonSize: 44,
                            onTap: () => _seekBy(-10),
                          ),
                          const SizedBox(width: 24),

                          // Center Play / Pause / Loading
                          if (_isBuffering)
                            Container(
                              width: 60,
                              height: 60,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                              child: const CircularProgressIndicator(
                                strokeWidth: 3.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFF59E0B),
                                ),
                              ),
                            )
                          else
                            _buildCircleButton(
                              icon: _isEnded
                                  ? Icons.replay_rounded
                                  : _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                              size: 38,
                              buttonSize: 60,
                              onTap: _togglePlayPause,
                              isPrimary: true,
                            ),
                          const SizedBox(width: 24),

                          // +10s Button
                          _buildCircleButton(
                            icon: Icons.forward_10_rounded,
                            size: 24,
                            buttonSize: 44,
                            onTap: () => _seekBy(10),
                          ),
                        ],
                      ),

                      // Bottom Controls Bar (Gradient scrim, time, amber scrubber, speed, fullscreen)
                      _buildBottomBar(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required double size,
    required double buttonSize,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: const Color(0xFFF59E0B).withValues(alpha: 0.3),
        highlightColor: Colors.white24,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPrimary
                ? const Color(0xFFF59E0B).withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.5),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            color: isPrimary ? Colors.black87 : Colors.white,
            size: size,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final maxMs = _totalDuration.inMilliseconds.toDouble();
    final curMs = _currentPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      padding: const EdgeInsets.only(left: 12, right: 8, bottom: 4, top: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrub Slider with live drag
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              trackShape: const RoundedRectSliderTrackShape(),
              activeTrackColor: const Color(0xFFF59E0B),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
              thumbColor: const Color(0xFFF59E0B),
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: _isScrubbing ? 7.5 : 5.5,
                pressedElevation: 4,
              ),
              overlayColor: const Color(0xFFF59E0B).withValues(alpha: 0.25),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: curMs,
              min: 0.0,
              max: maxMs > 0 ? maxMs : 1.0,
              onChangeStart: (val) {
                _hideTimer?.cancel();
                setState(() {
                  _isScrubbing = true;
                  _scrubValue = val;
                });
              },
              onChanged: (val) {
                setState(() {
                  _scrubValue = val;
                });
              },
              onChangeEnd: (val) {
                final target = Duration(milliseconds: val.toInt());
                if (widget.controller != null) {
                  widget.controller!.seekTo(target);
                } else {
                  widget.onSeek?.call(target);
                }
                setState(() {
                  _isScrubbing = false;
                });
                _startHideTimer();
              },
            ),
          ),

          // Bottom Info & Controls Row: [Current/Total] ... [Speed] [FullScreen]
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // Time Display
                Text(
                  '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),

                // Playback Speed Selector Popup
                PopupMenuButton<double>(
                  initialValue: _playbackRate,
                  tooltip: 'Playback Speed',
                  onOpened: () => _hideTimer?.cancel(),
                  onCanceled: _startHideTimer,
                  onSelected: _onSpeedSelected,
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (ctx) => _availableSpeeds.map((s) {
                    final isSelected = (s == _playbackRate);
                    return PopupMenuItem<double>(
                      value: s,
                      height: 38,
                      child: Row(
                        children: [
                          Text(
                            '${s}x',
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFFF59E0B)
                                  : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                          if (isSelected) ...[
                            const Spacer(),
                            const Icon(
                              Icons.check_rounded,
                              color: Color(0xFFF59E0B),
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_playbackRate}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Fullscreen Toggle Button
                if (widget.controller != null || widget.onToggleFullScreen != null)
                  IconButton(
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(
                      (widget.controller?.value.isFullScreen ?? widget.isFullScreen)
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Fullscreen',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (widget.controller != null) {
                        widget.controller!.toggleFullScreenMode();
                      } else {
                        widget.onToggleFullScreen?.call();
                      }
                      _startHideTimer();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
