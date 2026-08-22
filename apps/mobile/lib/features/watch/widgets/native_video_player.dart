import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt_iframe;
import 'package:url_launcher/url_launcher.dart';

class NativeVideoPlayer extends StatefulWidget {
  final String videoId;
  final String? thumbnailUrl;

  const NativeVideoPlayer({
    super.key,
    required this.videoId,
    this.thumbnailUrl,
  });

  @override
  State<NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<NativeVideoPlayer> {
  VideoPlayerController? _videoController;
  yt_iframe.YoutubePlayerController? _iframeController;

  bool _isLoading = true;
  bool _useIframeFallback = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _loadVideoStream();
  }

  @override
  void didUpdateWidget(covariant NativeVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _disposeControllers();
      _loadVideoStream();
    }
  }

  Future<void> _loadVideoStream() async {
    setState(() {
      _isLoading = true;
      _useIframeFallback = false;
    });

    try {
      final yt = YoutubeExplode();
      final manifest = await yt.videos.streamsClient.getManifest(widget.videoId);
      
      // Get best quality muxed stream (video + audio)
      var streamInfo = manifest.muxed.withHighestBitrate();
      yt.close();

      final streamUrl = streamInfo.url.toString();
      final controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      
      await controller.initialize();
      controller.play();

      if (mounted) {
        setState(() {
          _videoController = controller;
          _isLoading = false;
        });
        _startHideControlsTimer();
      }
    } catch (e) {
      debugPrint('Direct stream extraction failed ($e), falling back to IFrame player...');
      if (mounted) {
        _initIframeFallback();
      }
    }
  }

  void _initIframeFallback() {
    _iframeController = yt_iframe.YoutubePlayerController(
      params: const yt_iframe.YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        playsInline: true,
        origin: 'https://www.youtube-nocookie.com',
      ),
    );
    _iframeController!.loadVideoById(videoId: widget.videoId);

    setState(() {
      _useIframeFallback = true;
      _isLoading = false;
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _videoController?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
      setState(() => _showControls = true);
      _hideControlsTimer?.cancel();
    } else {
      _videoController!.play();
      setState(() => _showControls = true);
      _startHideControlsTimer();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _disposeControllers() {
    _hideControlsTimer?.cancel();
    _videoController?.dispose();
    _videoController = null;
    _iframeController?.close();
    _iframeController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
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

    if (_useIframeFallback && _iframeController != null) {
      return yt_iframe.YoutubePlayerScaffold(
        controller: _iframeController!,
        builder: (context, player) => player,
      );
    }

    if (_videoController != null && _videoController!.value.isInitialized) {
      final value = _videoController!.value;
      final position = value.position;
      final duration = value.duration;

      return GestureDetector(
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _startHideControlsTimer();
        },
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                  child: VideoPlayer(_videoController!),
                ),
              ),

              // Controls Overlay
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  color: Colors.black45,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          icon: const Icon(Icons.open_in_new, color: Colors.white),
                          tooltip: 'Open in YouTube',
                          onPressed: () async {
                            final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      ),

                      // Center Play / Pause
                      Center(
                        child: IconButton(
                          iconSize: 56,
                          icon: Icon(
                            value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),

                      // Bottom Scrubber & Timers
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        color: Colors.black54,
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Expanded(
                              child: Slider(
                                value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                                min: 0.0,
                                max: duration.inMilliseconds.toDouble(),
                                activeColor: const Color(0xFF3B82F6),
                                inactiveColor: Colors.white30,
                                onChanged: (val) {
                                  _videoController!.seekTo(Duration(milliseconds: val.toInt()));
                                  _startHideControlsTimer();
                                },
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Error Fallback
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_disabled, color: Colors.amber, size: 40),
          const SizedBox(height: 8),
          const Text(
            'Unable to stream directly in-app.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.play_arrow, color: Colors.red),
            label: const Text('Open in YouTube App'),
          ),
        ],
      ),
    );
  }
}
