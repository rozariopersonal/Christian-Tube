import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/models/local_short_item.dart';

class LocalShortPlayer extends StatefulWidget {
  final LocalShortItem item;
  final bool isPlaying;
  final Function(double currentSec, double totalSec)? onProgress;

  const LocalShortPlayer({
    super.key,
    required this.item,
    required this.isPlaying,
    this.onProgress,
  });

  @override
  State<LocalShortPlayer> createState() => _LocalShortPlayerState();
}

class _LocalShortPlayerState extends State<LocalShortPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant LocalShortPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.localVideoPath != widget.item.localVideoPath) {
      _disposePlayer();
      _initializePlayer();
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  Future<void> _initializePlayer() async {
    final path = widget.item.localVideoPath;
    if (path == null || path.isEmpty) {
      setState(() => _hasError = true);
      return;
    }

    try {
      if (!kIsWeb && io.File(path).existsSync()) {
        _controller = VideoPlayerController.file(io.File(path));
      } else {
        // Fallback for Web / simulated paths
        _controller = VideoPlayerController.networkUrl(
          Uri.parse('https://www.w3schools.com/html/mov_bbb.mp4'),
        );
      }

      await _controller!.initialize();
      _controller!.setLooping(true);

      _controller!.addListener(_onControllerUpdate);

      if (widget.isPlaying && mounted) {
        _controller!.play();
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('LocalShortPlayer init error: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;
    final curSec = value.position.inMilliseconds / 1000.0;
    final durSec = value.duration.inMilliseconds / 1000.0;
    widget.onProgress?.call(curSec, durSec);
  }

  void _disposePlayer() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || !_isInitialized || _controller == null) {
      // Background Sermon Thumbnail fallback while loading / rendering
      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.item.sourceVideoThumbnail != null && widget.item.sourceVideoThumbnail!.isNotEmpty)
              Image.network(
                widget.item.sourceVideoThumbnail!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0F172A)),
              )
            else
              Container(color: const Color(0xFF0F172A)),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black45,
                    Colors.transparent,
                    Colors.black87,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio > 0
              ? _controller!.value.aspectRatio
              : (9 / 16),
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}
