import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _showFeedback = false;
  bool _lastFeedbackIsPlaying = false;
  Timer? _feedbackTimer;

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
        hideThumbnail: true,
        useHybridComposition: true,
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
    _feedbackTimer?.cancel();
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    HapticFeedback.lightImpact();
    if (_controller == null) return;

    final isCurrentlyPlaying = _controller!.value.isPlaying;
    if (isCurrentlyPlaying) {
      _controller!.pause();
      _lastFeedbackIsPlaying = false;
    } else {
      _controller!.play();
      _lastFeedbackIsPlaying = true;
    }

    setState(() {
      _showFeedback = true;
    });

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showFeedback = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF59E0B),
            strokeWidth: 3,
          ),
        ),
      );
    }

    if (_controller != null) {
      final isVertical = widget.short.isVertical;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlayPause,
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
                      topActions: const [],
                      bottomActions: const [],
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
                      topActions: const [],
                      bottomActions: const [],
                    ),
                  ),
                ),

              // Smooth animated Play / Pause flash feedback
              Center(
                child: AnimatedOpacity(
                  opacity: _showFeedback ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                    child: Icon(
                      _lastFeedbackIsPlaying
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 54,
                      color: Colors.white,
                    ),
                  ),
                ),
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
