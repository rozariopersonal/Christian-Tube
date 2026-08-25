import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:url_launcher/url_launcher.dart';

class NativeVideoPlayer extends StatefulWidget {
  final String videoId;
  final String? videoTitle;
  final String? thumbnailUrl;
  final VoidCallback? onVideoEnded;
  final VoidCallback? onSwitchToIframe;

  const NativeVideoPlayer({
    super.key,
    required this.videoId,
    this.videoTitle,
    this.thumbnailUrl,
    this.onVideoEnded,
    this.onSwitchToIframe,
  });

  @override
  State<NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<NativeVideoPlayer> {
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;
  Timer? _doubleTapTimer;

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
      _errorMessage = null;
    });

    YoutubeExplode? yt;
    try {
      yt = YoutubeExplode();
      final manifest = await yt.videos.streamsClient.getManifest(widget.videoId);

      // Prefer highest bitrate muxed stream (video + audio in single stream)
      StreamInfo? selectedStream;
      if (manifest.muxed.isNotEmpty) {
        selectedStream = manifest.muxed.withHighestBitrate();
      }

      if (selectedStream == null) {
        throw Exception('No playable video stream found');
      }

      final streamUrl = selectedStream.url.toString();
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      await controller.initialize();
      controller.play();

      controller.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _videoController = controller;
          _isLoading = false;
        });
        _startHideControlsTimer();
      }
    } catch (e) {
      debugPrint('Direct stream extraction error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Stream playback error: $e';
        });
      }
    } finally {
      yt?.close();
    }
  }

  void _videoListener() {
    if (_videoController == null || !mounted) return;
    final value = _videoController!.value;
    if (value.position >= value.duration && value.duration > Duration.zero) {
      widget.onVideoEnded?.call();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
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

  void _seekRelative(int seconds) {
    if (_videoController == null) return;
    final current = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);

    _videoController!.seekTo(clamped);
    setState(() => _showControls = true);
    _startHideControlsTimer();

    if (seconds < 0) {
      setState(() => _showDoubleTapLeft = true);
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showDoubleTapLeft = false);
      });
    } else {
      setState(() => _showDoubleTapRight = true);
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showDoubleTapRight = false);
      });
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _disposeControllers() {
    _hideControlsTimer?.cancel();
    _doubleTapTimer?.cancel();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _videoController = null;
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
          child: CircularProgressIndicator(color: Colors.red, strokeWidth: 3),
        ),
      );
    }

    if (_errorMessage != null || _videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.amber, size: 40),
            const SizedBox(height: 8),
            const Text(
              'Playback temporarily restricted by YouTube.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.onSwitchToIframe != null) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: widget.onSwitchToIframe,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry Iframe'),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in YouTube'),
                ),
              ],
            ),
          ],
        ),
      );
    }

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

            // Double Tap Seek Left Detector
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => _seekRelative(-10),
                child: _showDoubleTapLeft
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.replay_10, color: Colors.white, size: 28),
                              Text('-10s', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Double Tap Seek Right Detector
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => _seekRelative(10),
                child: _showDoubleTapRight
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.forward_10, color: Colors.white, size: 28),
                              Text('+10s', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Controls Overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: Colors.black38,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.videoTitle ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (widget.onSwitchToIframe != null)
                            IconButton(
                              icon: const Icon(Icons.sync_alt, color: Colors.white70, size: 20),
                              tooltip: 'Switch to YouTube Embed',
                              onPressed: widget.onSwitchToIframe,
                            ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, color: Colors.white70, size: 20),
                            tooltip: 'Open in YouTube',
                            onPressed: () async {
                              final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Center Controls (Rewind 10, Play/Pause, Forward 10)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.replay_10, color: Colors.white),
                          onPressed: () => _seekRelative(-10),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          iconSize: 56,
                          icon: Icon(
                            value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.forward_10, color: Colors.white),
                          onPressed: () => _seekRelative(10),
                        ),
                      ],
                    ),

                    // Bottom Bar (Scrubber + Duration)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Direct Stream',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: Colors.red,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.red,
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                            min: 0.0,
                            max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                            onChanged: (val) {
                              _videoController!.seekTo(Duration(milliseconds: val.toInt()));
                              _startHideControlsTimer();
                            },
                          ),
                        ),
                      ],
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
}
