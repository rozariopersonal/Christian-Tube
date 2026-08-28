// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../widgets/flutter_video_controls_overlay.dart';

final Set<String> _registeredVideoViews = {};

void pausePlatformMainVideo() {
  try {
    final iframes = html.document.querySelectorAll('iframe');
    for (final elem in iframes) {
      if (elem is html.IFrameElement) {
        elem.contentWindow?.postMessage(
          '{"event":"command","func":"pauseVideo","args":""}',
          '*',
        );
      }
    }
  } catch (_) {}
}

Widget buildPlatformVideoPlayer({
  required String videoId,
  double? startSeconds,
  ValueChanged<Duration>? onPositionChanged,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _WebVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    onPositionChanged: onPositionChanged,
    builder: builder,
  );
}

class _WebVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final ValueChanged<Duration>? onPositionChanged;
  final Widget Function(BuildContext context, Widget player) builder;

  const _WebVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
    this.onPositionChanged,
    required this.builder,
  });

  @override
  State<_WebVideoPlayerWrapper> createState() => _WebVideoPlayerWrapperState();
}

class _WebVideoPlayerWrapperState extends State<_WebVideoPlayerWrapper> {
  late String _viewId;
  html.IFrameElement? _iframe;
  StreamSubscription? _msgSub;
  Timer? _ticker;

  bool _isPlaying = true;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 10);
  double _playbackRate = 1.0;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _initView();
    _listenToIframeEvents();
    _startPositionTicker();
  }

  @override
  void didUpdateWidget(covariant _WebVideoPlayerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _position = Duration.zero;
      _isPlaying = true;
      _initView();
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _startPositionTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isPlaying && mounted) {
        setState(() {
          final nextMs = _position.inMilliseconds + (500 * _playbackRate).toInt();
          _position = Duration(
            milliseconds: nextMs.clamp(0, _duration.inMilliseconds),
          );
          widget.onPositionChanged?.call(_position);
        });
      }
    });
  }

  void _listenToIframeEvents() {
    _msgSub = html.window.onMessage.listen((event) {
      try {
        if (event.data is String) {
          final data = jsonDecode(event.data);
          if (data is Map && data['event'] == 'infoDelivery') {
            final info = data['info'];
            if (info is Map) {
              if (info['currentTime'] != null) {
                final sec = (info['currentTime'] as num).toDouble();
                _position = Duration(milliseconds: (sec * 1000).toInt());
                widget.onPositionChanged?.call(_position);
              }
              if (info['duration'] != null && (info['duration'] as num) > 0) {
                final durSec = (info['duration'] as num).toDouble();
                _duration = Duration(milliseconds: (durSec * 1000).toInt());
              }
              if (info['playerState'] != null) {
                final state = info['playerState'];
                // 1: playing, 2: paused, 3: buffering, 0: ended
                if (state == 1) {
                  _isPlaying = true;
                  _isBuffering = false;
                } else if (state == 2) {
                  _isPlaying = false;
                  _isBuffering = false;
                } else if (state == 3) {
                  _isBuffering = true;
                } else if (state == 0) {
                  _isPlaying = false;
                  _isBuffering = false;
                }
              }
              if (mounted) setState(() {});
            }
          }
        }
      } catch (_) {}
    });
  }

  void _sendCommand(String func, [List<dynamic> args = const []]) {
    try {
      final msg = jsonEncode({
        'event': 'command',
        'func': func,
        'args': args,
      });
      _iframe?.contentWindow?.postMessage(msg, '*');
    } catch (_) {}
  }

  void _initView() {
    _viewId = 'video-player-${widget.videoId}-${DateTime.now().millisecondsSinceEpoch}';
    if (!_registeredVideoViews.contains(_viewId)) {
      _registeredVideoViews.add(_viewId);
      final startParam = (widget.startSeconds != null && widget.startSeconds! > 0)
          ? '&start=${widget.startSeconds!.toInt()}'
          : '';

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) {
          final origin = html.window.location.origin;
          final iframe = html.IFrameElement()
            ..src =
                'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&mute=0&playsinline=1&controls=0&rel=0&modestbranding=1&enablejsapi=1&origin=$origin$startParam'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow =
                'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
            ..allowFullscreen = true;
          _iframe = iframe;
          return iframe;
        },
      );
    }
  }

  void _onPlay() {
    _sendCommand('playVideo');
    setState(() => _isPlaying = true);
  }

  void _onPause() {
    _sendCommand('pauseVideo');
    setState(() => _isPlaying = false);
  }

  void _onSeek(Duration pos) {
    final sec = pos.inMilliseconds / 1000.0;
    _sendCommand('seekTo', [sec, true]);
    setState(() => _position = pos);
  }

  void _onSetSpeed(double speed) {
    _sendCommand('setPlaybackRate', [speed]);
    setState(() => _playbackRate = speed);
  }

  void _onToggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerWidget = AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: HtmlElementView(viewType: _viewId),
          ),
          FlutterVideoControlsOverlay(
            isPlaying: _isPlaying,
            isBuffering: _isBuffering,
            position: _position,
            duration: _duration,
            playbackRate: _playbackRate,
            isFullScreen: _isFullScreen,
            onPlay: _onPlay,
            onPause: _onPause,
            onSeek: _onSeek,
            onSetSpeed: _onSetSpeed,
            onToggleFullScreen: _onToggleFullScreen,
          ),
        ],
      ),
    );

    return widget.builder(context, playerWidget);
  }
}
