import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth/auth_service.dart';
import '../../../../core/models/local_short_item.dart';
import '../../shorts/services/shorts_orchestrator_service.dart';
import '../players/universal_video_player.dart';
import 'clip_preview_player.dart';

class ShortsTrimmerSheet extends StatefulWidget {
  final String sourceVideoId;
  final String sourceVideoTitle;
  final String? sourceVideoThumbnail;
  final double currentPlayheadSeconds;
  final double totalDurationSeconds;
  final Function(double timestamp)? onLiveSeek;

  const ShortsTrimmerSheet({
    super.key,
    required this.sourceVideoId,
    required this.sourceVideoTitle,
    this.sourceVideoThumbnail,
    required this.currentPlayheadSeconds,
    required this.totalDurationSeconds,
    this.onLiveSeek,
  });

  @override
  State<ShortsTrimmerSheet> createState() => _ShortsTrimmerSheetState();
}

class _ShortsTrimmerSheetState extends State<ShortsTrimmerSheet> {
  final AuthService _authService = AuthService();
  final GlobalKey<ClipPreviewPlayerState> _previewPlayerKey = GlobalKey();
  final ValueNotifier<double> _livePlayheadNotifier = ValueNotifier(0.0);

  late TextEditingController _titleController;
  late TextEditingController _creatorNameController;
  late TextEditingController _creatorEmailController;

  late double _totalDuration;
  double _clipDuration = 60.0; // 15s to 180s (Default: 60s)
  late double _clipStartTime;

  ShortsFramingMode _framingMode = ShortsFramingMode.portrait9x16;
  double _cropOffsetX = 0.0; // -1.0 (Left Stage) to +1.0 (Right Stage), 0.0 (Center)
  bool _isLooping = true;

  Timer? _seekThrottleTimer;
  final ScrollController _timelineScrollController = ScrollController();

  double get _clipEndTime =>
      (_clipStartTime + _clipDuration).clamp(0.0, _totalDuration);

  @override
  void initState() {
    super.initState();
    // Pause main background video when trimmer opens
    pausePlatformMainVideo();

    _totalDuration = widget.totalDurationSeconds > 0
        ? widget.totalDurationSeconds
        : 1800.0;

    // Auto-capture preceding 60 seconds up to current playhead
    final playhead = widget.currentPlayheadSeconds.clamp(0.0, _totalDuration);
    _clipDuration = 60.0.clamp(15.0, _totalDuration);
    _clipStartTime =
        (playhead - _clipDuration).clamp(0.0, _totalDuration - _clipDuration);
    _livePlayheadNotifier.value = _clipStartTime;

    final cleanTitle = widget.sourceVideoTitle.trim();
    final initialTitle = cleanTitle.isNotEmpty
        ? '$cleanTitle #Shorts'
        : 'Inspirational Short #Shorts';
    _titleController = TextEditingController(text: initialTitle);

    final currentUser = _authService.currentUser;
    _creatorNameController = TextEditingController(
      text: (currentUser?.displayName != null && currentUser!.displayName!.isNotEmpty)
          ? currentUser.displayName!
          : 'Believer in Christ',
    );
    _creatorEmailController = TextEditingController(
      text: currentUser?.email ?? '',
    );
  }

  @override
  void dispose() {
    _seekThrottleTimer?.cancel();
    _timelineScrollController.dispose();
    _livePlayheadNotifier.dispose();
    _titleController.dispose();
    _creatorNameController.dispose();
    _creatorEmailController.dispose();
    super.dispose();
  }

  void _triggerThrottledSeek(double timestamp) {
    _livePlayheadNotifier.value = timestamp;
    if (_seekThrottleTimer?.isActive ?? false) return;

    _seekThrottleTimer = Timer(const Duration(milliseconds: 75), () {
      _previewPlayerKey.currentState?.seekTo(timestamp);
      widget.onLiveSeek?.call(timestamp);
    });
  }

  void _nudgeStartTime(double deltaSec) {
    HapticFeedback.selectionClick();
    setState(() {
      final newStart = (_clipStartTime + deltaSec).clamp(
        0.0,
        _totalDuration - _clipDuration,
      );
      _clipStartTime = newStart;
    });
    _triggerThrottledSeek(_clipStartTime);
  }

  void _nudgeEndTime(double deltaSec) {
    HapticFeedback.selectionClick();
    setState(() {
      final newDur = (_clipDuration + deltaSec).clamp(15.0, 180.0);
      if (_clipStartTime + newDur <= _totalDuration) {
        _clipDuration = newDur;
      } else {
        _clipDuration = _totalDuration - _clipStartTime;
      }
    });
    _triggerThrottledSeek(_clipStartTime);
  }

  void _snapToPlayhead() {
    HapticFeedback.mediumImpact();
    setState(() {
      _clipStartTime = (widget.currentPlayheadSeconds - (_clipDuration / 2))
          .clamp(0.0, _totalDuration - _clipDuration);
    });
    _triggerThrottledSeek(_clipStartTime);
  }

  void _setDurationPreset(double duration) {
    HapticFeedback.selectionClick();
    setState(() {
      _clipDuration = duration.clamp(15.0, _totalDuration);
      if (_clipStartTime + _clipDuration > _totalDuration) {
        _clipStartTime =
            (_totalDuration - _clipDuration).clamp(0.0, _totalDuration);
      }
    });
    _triggerThrottledSeek(_clipStartTime);
  }

  String _getTimelineThumbnailUrl(int index, int totalCount) {
    if (widget.sourceVideoId.isEmpty) {
      return widget.sourceVideoThumbnail ?? '';
    }
    // YouTube distributes 3 frame snapshots (1.jpg, 2.jpg, 3.jpg) across ~25%, ~50%, ~75%
    // and hqdefault.jpg as the start/cover frame.
    final ratio = index / (totalCount - 1);
    if (ratio <= 0.15) {
      return 'https://img.youtube.com/vi/${widget.sourceVideoId}/hqdefault.jpg';
    } else if (ratio <= 0.45) {
      return 'https://img.youtube.com/vi/${widget.sourceVideoId}/1.jpg';
    } else if (ratio <= 0.75) {
      return 'https://img.youtube.com/vi/${widget.sourceVideoId}/2.jpg';
    } else {
      return 'https://img.youtube.com/vi/${widget.sourceVideoId}/3.jpg';
    }
  }

  String _formatSeconds(double sec) {
    final totalSec = sec.toInt();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onPublish() async {
    final title = _titleController.text.trim();
    final creatorName = _creatorNameController.text.trim();
    final creatorEmail = _creatorEmailController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a title for your Short')),
      );
      return;
    }

    // Launch background job with framing & crop offsets
    ShortsOrchestratorService().createShort(
      sourceVideoId: widget.sourceVideoId,
      sourceVideoTitle: widget.sourceVideoTitle,
      sourceVideoThumbnail: widget.sourceVideoThumbnail,
      title: title,
      creatorName: creatorName.isNotEmpty ? creatorName : 'Anonymous',
      creatorEmail: creatorEmail,
      clipStartTime: _clipStartTime,
      clipEndTime: _clipEndTime,
      cropOffsetX: _cropOffsetX,
      framingMode: _framingMode,
    );

    // Dismiss bottom sheet immediately so user can resume watching
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '✂️ Clipping Short (${_formatSeconds(_clipDuration)})... You can check progress under "My Creations"!',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final is9x16 = _framingMode == ShortsFramingMode.portrait9x16;

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Sheet Drag Handle & Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.content_cut, color: Color(0xFFF59E0B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Create Short (Up to 3 mins)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. EMBEDDED LIVE PREVIEW WITH DIRECT 9:16 CROP VIEWFINDER
                  ClipPreviewPlayer(
                    key: _previewPlayerKey,
                    videoId: widget.sourceVideoId,
                    videoThumbnail: widget.sourceVideoThumbnail,
                    clipStartTime: _clipStartTime,
                    clipEndTime: _clipEndTime,
                    framingMode: _framingMode,
                    cropOffsetX: _cropOffsetX,
                    onCropOffsetChanged: (newOffset) {
                      _cropOffsetX = newOffset;
                    },
                    isLooping: _isLooping,
                    onPositionChanged: (pos) {
                      _livePlayheadNotifier.value = pos;
                    },
                  ),

                  // 2. VIEWFINDER DRAG HINT & TOOLBAR
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Framing Style Switch (9:16 Vertical Short vs 16:9 Landscape)
                      Row(
                        children: [
                          _buildFramingPill(
                            mode: ShortsFramingMode.portrait9x16,
                            label: '9:16 Short',
                            icon: Icons.crop_portrait,
                          ),
                          const SizedBox(width: 6),
                          _buildFramingPill(
                            mode: ShortsFramingMode.landscape16x9,
                            label: '16:9 Landscape',
                            icon: Icons.stay_current_landscape,
                          ),
                        ],
                      ),

                      // Play/Pause & Loop preview toggles
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _previewPlayerKey.currentState?.togglePlayPause();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 13,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Play/Pause',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Loop preview toggle
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _isLooping = !_isLooping;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isLooping ? const Color(0xFFF59E0B) : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.repeat,
                                    size: 12,
                                    color: _isLooping ? const Color(0xFFF59E0B) : Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isLooping ? 'Loop On' : 'Loop Off',
                                    style: TextStyle(
                                      color: _isLooping ? const Color(0xFFF59E0B) : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (is9x16) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: const [
                        Icon(Icons.touch_app_outlined, color: Color(0xFFF59E0B), size: 13),
                        SizedBox(width: 5),
                        Text(
                          'Drag on the preview to move the 9:16 crop window across the stage',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 18),

                  // 3. TIMELINE TRACK & FINE-TUNE SCRUBBING
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'POSITION IN FULL VIDEO',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          '${_formatSeconds(_clipStartTime)}  ➔  ${_formatSeconds(_clipEndTime)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Interactive Timeline Scrubber Bar with Live Needle
                  Container(
                    height: 48,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final trackWidth = constraints.maxWidth;
                        final double startPct =
                            (_clipStartTime / _totalDuration).clamp(0.0, 1.0);
                        final double durationPct =
                            (_clipDuration / _totalDuration).clamp(0.05, 1.0);
                        final double endPct =
                            (startPct + durationPct).clamp(0.0, 1.0);

                        const int thumbnailCount = 10;

                        return Stack(
                          children: [
                            // 1. Filmstrip of Real Frame Thumbnails
                            Positioned.fill(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: List.generate(
                                  thumbnailCount,
                                  (i) => Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.black
                                                .withValues(alpha: 0.45),
                                            width: 1.0,
                                          ),
                                        ),
                                      ),
                                      child: CachedNetworkImage(
                                        imageUrl: _getTimelineThumbnailUrl(
                                            i, thumbnailCount),
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(
                                          color: const Color(0xFF1E293B),
                                          child: const Center(
                                            child: SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.5,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                            Color>(
                                                        Colors.white24),
                                              ),
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                          color: const Color(0xFF1E293B),
                                          child: const Icon(
                                            Icons.movie_creation_outlined,
                                            color: Colors.white24,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 2. Inactive Region Dimming Overlays
                            // Left unselected region
                            if (startPct > 0)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                width: startPct * trackWidth,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                              ),

                            // Right unselected region
                            if (endPct < 1.0)
                              Positioned(
                                left: endPct * trackWidth,
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                              ),

                            // 3. Highlight Window (Selected Clip Box with Tactile Handles)
                            Positioned(
                              left: startPct * trackWidth,
                              width: (durationPct * trackWidth)
                                  .clamp(trackWidth * 0.15, trackWidth),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B),
                                    width: 2.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      spreadRadius: 0.5,
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Left Handle Grip Bar
                                    Positioned(
                                      left: 2,
                                      top: 10,
                                      bottom: 10,
                                      child: Container(
                                        width: 3.5,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                    // Center Duration Pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.75),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFFF59E0B),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        _formatSeconds(_clipDuration),
                                        style: const TextStyle(
                                          color: Color(0xFFF59E0B),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    // Right Handle Grip Bar
                                    Positioned(
                                      right: 2,
                                      top: 10,
                                      bottom: 10,
                                      child: Container(
                                        width: 3.5,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 4. Live Playhead Scrubber Needle
                            ValueListenableBuilder<double>(
                              valueListenable: _livePlayheadNotifier,
                              builder: (context, livePlayhead, _) {
                                final double livePct =
                                    (livePlayhead / _totalDuration)
                                        .clamp(0.0, 1.0);
                                return Positioned(
                                  left: (livePct * trackWidth)
                                      .clamp(0.0, trackWidth - 2.5),
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 2.5,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.amber
                                              .withValues(alpha: 0.9),
                                          blurRadius: 5,
                                          spreadRadius: 1.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            // 5. Gesture Detector over track to live scrub & seek
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (details) {
                                  final double deltaPct =
                                      details.primaryDelta! / trackWidth;
                                  final double deltaSec =
                                      deltaPct * _totalDuration;
                                  setState(() {
                                    _clipStartTime =
                                        (_clipStartTime + deltaSec).clamp(
                                      0.0,
                                      _totalDuration - _clipDuration,
                                    );
                                  });
                                  _triggerThrottledSeek(_clipStartTime);
                                },
                                onTapDown: (details) {
                                  final tapX = details.localPosition.dx;
                                  final tapPct =
                                      (tapX / trackWidth).clamp(0.0, 1.0);
                                  final tapSec = tapPct * _totalDuration;
                                  setState(() {
                                    _clipStartTime =
                                        (tapSec - (_clipDuration / 2))
                                            .clamp(
                                      0.0,
                                      _totalDuration - _clipDuration,
                                    );
                                  });
                                  _triggerThrottledSeek(_clipStartTime);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Precision Nudge Buttons Bar: [-1s], [+1s] and Snap Playhead
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Start Nudge
                      Row(
                        children: [
                          const Text('Start: ',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                          _buildNudgeBtn('-1s', () => _nudgeStartTime(-1.0)),
                          const SizedBox(width: 4),
                          _buildNudgeBtn('+1s', () => _nudgeStartTime(1.0)),
                        ],
                      ),
                      // Snap to video playhead
                      InkWell(
                        onTap: _snapToPlayhead,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.my_location,
                                  size: 12, color: Colors.white70),
                              SizedBox(width: 4),
                              Text(
                                'Snap Playhead',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // End Nudge
                      Row(
                        children: [
                          const Text('End: ',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                          _buildNudgeBtn('-1s', () => _nudgeEndTime(-1.0)),
                          const SizedBox(width: 4),
                          _buildNudgeBtn('+1s', () => _nudgeEndTime(1.0)),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 4. DURATION CONTROL & PRESETS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CLIP DURATION',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Text(
                          _formatSeconds(_clipDuration),
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Quick Presets: 15s, 30s, 60s, 180s
                  Row(
                    children: [
                      _buildPresetChip('15s', 15.0),
                      const SizedBox(width: 8),
                      _buildPresetChip('30s', 30.0),
                      const SizedBox(width: 8),
                      _buildPresetChip('60s (Standard)', 60.0),
                      const SizedBox(width: 8),
                      _buildPresetChip('180s (Max)', 180.0),
                    ],
                  ),

                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: const Color(0xFFF59E0B),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFFF59E0B),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 10),
                      overlayColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      valueIndicatorColor: const Color(0xFFF59E0B),
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: _clipDuration,
                      min: 15.0,
                      max: 180.0,
                      divisions: 33,
                      label: _formatSeconds(_clipDuration),
                      onChanged: (val) {
                        setState(() {
                          _clipDuration = val;
                          if (_clipStartTime + _clipDuration > _totalDuration) {
                            _clipStartTime = (_totalDuration - _clipDuration)
                                .clamp(0.0, _totalDuration);
                          }
                        });
                        _triggerThrottledSeek(_clipStartTime);
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 5. METADATA INPUTS
                  const Text(
                    'SHORT DETAILS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Title Field
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Short Title',
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Creator Name Field
                  TextField(
                    controller: _creatorNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Clipped by (Your Name)',
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 6. PUBLISH BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _onPublish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.rocket_launch, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Publish Short (720p)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFramingPill({
    required ShortsFramingMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _framingMode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _framingMode = mode;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? const Color(0xFFF59E0B) : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFF59E0B) : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNudgeBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, double duration) {
    final isSelected = (_clipDuration - duration).abs() < 1.0;
    return InkWell(
      onTap: () => _setDurationPreset(duration),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
