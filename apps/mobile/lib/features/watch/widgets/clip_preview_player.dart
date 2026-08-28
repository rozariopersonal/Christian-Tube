import 'package:flutter/material.dart';
import '../../../../core/models/local_short_item.dart';
import 'preview/clip_preview_platform.dart';

class ClipPreviewPlayer extends StatefulWidget {
  final String videoId;
  final String? videoThumbnail;
  final double clipStartTime;
  final double clipEndTime;
  final ShortsFramingMode framingMode;
  final double cropOffsetX;
  final ValueChanged<double>? onCropOffsetChanged;
  final bool isLooping;
  final ValueChanged<double>? onPositionChanged;
  final VoidCallback? onTogglePlayPause;

  const ClipPreviewPlayer({
    super.key,
    required this.videoId,
    this.videoThumbnail,
    required this.clipStartTime,
    required this.clipEndTime,
    this.framingMode = ShortsFramingMode.portrait9x16,
    this.cropOffsetX = 0.0,
    this.onCropOffsetChanged,
    this.isLooping = true,
    this.onPositionChanged,
    this.onTogglePlayPause,
  });

  @override
  State<ClipPreviewPlayer> createState() => ClipPreviewPlayerState();
}

class ClipPreviewPlayerState extends State<ClipPreviewPlayer> {
  final GlobalKey _platformKey = GlobalKey();

  void seekTo(double seconds) {
    final state = _platformKey.currentState;
    if (state != null) {
      try {
        (state as dynamic).seekTo(seconds);
      } catch (_) {}
    }
  }

  void togglePlayPause() {
    final state = _platformKey.currentState;
    if (state != null) {
      try {
        (state as dynamic).togglePlayPause();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildPlatformClipPreview(
      key: _platformKey,
      videoId: widget.videoId,
      videoThumbnail: widget.videoThumbnail,
      clipStartTime: widget.clipStartTime,
      clipEndTime: widget.clipEndTime,
      framingMode: widget.framingMode,
      cropOffsetX: widget.cropOffsetX,
      onCropOffsetChanged: widget.onCropOffsetChanged,
      isLooping: widget.isLooping,
      onPositionChanged: widget.onPositionChanged,
      onTogglePlayPause: widget.onTogglePlayPause,
    );
  }
}
