import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../core/models/short.dart';

class NativeShortsPlayer extends StatefulWidget {
  final Short short;
  final bool isPlaying;

  const NativeShortsPlayer({
    super.key,
    required this.short,
    required this.isPlaying,
  });

  @override
  State<NativeShortsPlayer> createState() => _NativeShortsPlayerState();
}

class _NativeShortsPlayerState extends State<NativeShortsPlayer> {
  YoutubePlayerController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    _controller = YoutubePlayerController(
      initialVideoId: widget.short.id,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        hideControls: true,
        disableDragSeek: true,
        loop: true,
      ),
    );

    if (widget.isPlaying && mounted) {
      _controller!.play();
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void didUpdateWidget(covariant NativeShortsPlayer oldWidget) {
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_controller != null) {
      return GestureDetector(
        onTap: () {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          } else {
            _controller!.play();
          }
          setState(() {});
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Using FittedBox to try to cover the screen 9:16 aspect ratio
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width * (16 / 9),
                child: IgnorePointer(
                  child: YoutubePlayer(
                    controller: _controller!,
                    showVideoProgressIndicator: false,
                  ),
                ),
              ),
            ),
            
            // Play/Pause overlay indicator
            if (!_controller!.value.isPlaying)
              const Center(
                child: Icon(Icons.play_arrow, size: 64, color: Colors.white70),
              ),
          ],
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
