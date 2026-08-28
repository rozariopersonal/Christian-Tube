import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../widgets/flutter_video_controls_overlay.dart';

void pausePlatformMainVideo() {}

Widget buildPlatformVideoPlayer({
  required String videoId,
  double? startSeconds,
  ValueChanged<Duration>? onPositionChanged,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _MobileVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    onPositionChanged: onPositionChanged,
    builder: builder,
  );
}

class _MobileVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final ValueChanged<Duration>? onPositionChanged;
  final Widget Function(BuildContext context, Widget player) builder;

  const _MobileVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
    this.onPositionChanged,
    required this.builder,
  });

  @override
  State<_MobileVideoPlayerWrapper> createState() =>
      _MobileVideoPlayerWrapperState();
}

class _MobileVideoPlayerWrapperState extends State<_MobileVideoPlayerWrapper> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _initController(widget.videoId);
    // Allow sensor auto-rotation while on video player screen
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _initController(String videoId) {
    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
        hideControls: true,
        hideThumbnail: true,
        useHybridComposition: true,
        startAt: widget.startSeconds != null ? widget.startSeconds!.toInt() : 0,
      ),
    )..addListener(_handleControllerUpdate);
  }

  void _handleControllerUpdate() {
    if (mounted && widget.onPositionChanged != null) {
      widget.onPositionChanged!(_controller.value.position);
    }
  }

  @override
  void didUpdateWidget(covariant _MobileVideoPlayerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _controller.load(widget.videoId);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      onEnterFullScreen: () {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      },
      onExitFullScreen: () {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        // Re-enable smooth auto-rotation after exit
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            SystemChrome.setPreferredOrientations(DeviceOrientation.values);
          }
        });
      },
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: false,
        topActions: const [],
        bottomActions: const [],
      ),
      builder: (context, playerWidget) {
        final decoratedPlayer = AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              playerWidget,
              FlutterVideoControlsOverlay(
                controller: _controller,
              ),
            ],
          ),
        );
        return widget.builder(context, decoratedPlayer);
      },
    );
  }
}
