import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _streamUrl;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.short.directStreamUrl != null) {
        _streamUrl = widget.short.directStreamUrl;
      } else {
        // Extract direct stream using youtube_explode_dart
        final yt = YoutubeExplode();
        final manifest = await yt.videos.streamsClient.getManifest(widget.short.id);
        final streamInfo = manifest.muxed.withHighestBitrate();
        _streamUrl = streamInfo.url.toString();
        yt.close();
      }

      if (_streamUrl != null) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(_streamUrl!));
        await _controller!.initialize();
        _controller!.setLooping(true);

        if (widget.isPlaying && mounted) {
          _controller!.play();
        }
      }
    } catch (e) {
      debugPrint('Error playing short: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant NativeShortsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null && _controller!.value.isInitialized) {
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

    if (_controller != null && _controller!.value.isInitialized) {
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
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
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
