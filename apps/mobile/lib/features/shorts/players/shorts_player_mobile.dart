import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../core/models/short.dart';

void stopAllPlatformShorts() {}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
}) {
  return _MobileShortsPlayerWidget(
    short: short,
    isPlaying: isPlaying,
  );
}

class _MobileShortsPlayerWidget extends StatefulWidget {
  final Short short;
  final bool isPlaying;

  const _MobileShortsPlayerWidget({
    required this.short,
    required this.isPlaying,
  });

  @override
  State<_MobileShortsPlayerWidget> createState() =>
      _MobileShortsPlayerWidgetState();
}

class _MobileShortsPlayerWidgetState extends State<_MobileShortsPlayerWidget> {
  YoutubePlayerController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    _controller = YoutubePlayerController(
      initialVideoId: widget.short.id,
      flags: YoutubePlayerFlags(
        autoPlay: widget.isPlaying,
        mute: false,
        hideControls: true,
        disableDragSeek: true,
        loop: true,
        enableCaption: false,
      ),
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void didUpdateWidget(covariant _MobileShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null) {
      if (widget.isPlaying && !oldWidget.isPlaying) {
        _controller!.play();
      } else if (!widget.isPlaying && oldWidget.isPlaying) {
        _controller!.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_controller != null) {
      final isVertical = widget.short.isVertical;

      return GestureDetector(
        onTap: () {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          } else {
            _controller!.play();
          }
          setState(() {});
        },
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Ambient blurred background for horizontal videos
              if (!isVertical) ...[
                Positioned.fill(
                  child: Image.network(
                    widget.short.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                ),
              ],

              // Main Video Player with correct aspect ratio
              if (isVertical)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width * (16 / 9),
                    child: YoutubePlayer(
                      controller: _controller!,
                      showVideoProgressIndicator: false,
                    ),
                  ),
                )
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: YoutubePlayer(
                      controller: _controller!,
                      showVideoProgressIndicator: false,
                    ),
                  ),
                ),

              if (!_controller!.value.isPlaying)
                const Center(
                  child: Icon(Icons.play_arrow, size: 64, color: Colors.white70),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.error_outline, color: Colors.white54, size: 48),
      ),
    );
  }
}
