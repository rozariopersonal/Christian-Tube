import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

Widget buildPlatformVideoPlayer({
  required String videoId,
  double? startSeconds,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _MobileVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    builder: builder,
  );
}

class _MobileVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final Widget Function(BuildContext context, Widget player) builder;

  const _MobileVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
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
        enableCaption: true,
        startAt: widget.startSeconds != null ? widget.startSeconds!.toInt() : 0,
      ),
    );
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
        showVideoProgressIndicator: true,
        progressIndicatorColor: const Color(0xFFF59E0B),
        progressColors: const ProgressBarColors(
          playedColor: Color(0xFFF59E0B),
          handleColor: Color(0xFFF59E0B),
        ),
      ),
      builder: widget.builder,
    );
  }
}
