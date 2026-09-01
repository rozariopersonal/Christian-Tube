import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/models/local_short_item.dart';

final Set<String> _registeredClipViews = {};

Widget buildPlatformClipPreview({
  Key? key,
  required String videoId,
  String? videoThumbnail,
  required double clipStartTime,
  required double clipEndTime,
  required ShortsFramingMode framingMode,
  double cropOffsetX = 0.0,
  ValueChanged<double>? onCropOffsetChanged,
  required bool isLooping,
  ValueChanged<double>? onPositionChanged,
  VoidCallback? onTogglePlayPause,
}) {
  return _WebClipPreviewWidget(
    key: key,
    videoId: videoId,
    videoThumbnail: videoThumbnail,
    clipStartTime: clipStartTime,
    clipEndTime: clipEndTime,
    framingMode: framingMode,
    cropOffsetX: cropOffsetX,
    onCropOffsetChanged: onCropOffsetChanged,
    isLooping: isLooping,
    onPositionChanged: onPositionChanged,
    onTogglePlayPause: onTogglePlayPause,
  );
}

class _WebClipPreviewWidget extends StatefulWidget {
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

  const _WebClipPreviewWidget({
    super.key,
    required this.videoId,
    this.videoThumbnail,
    required this.clipStartTime,
    required this.clipEndTime,
    required this.framingMode,
    this.cropOffsetX = 0.0,
    this.onCropOffsetChanged,
    required this.isLooping,
    this.onPositionChanged,
    this.onTogglePlayPause,
  });

  @override
  State<_WebClipPreviewWidget> createState() => WebClipPreviewWidgetState();
}

class WebClipPreviewWidgetState extends State<_WebClipPreviewWidget> {
  late String _viewId;
  html.IFrameElement? _iframeElement;
  StreamSubscription? _msgSub;
  Timer? _loopTicker;
  double _currentPosition = 0.0;
  double _localCropOffset = 0.0;
  bool _isDraggingCrop = false;
  double _dragDistance = 0.0;
  bool _isPlaying = true;
  bool _showFeedback = false;
  Timer? _feedbackTimer;

  String get _thumbnailUrl =>
      widget.videoThumbnail?.isNotEmpty == true
          ? widget.videoThumbnail!
          : 'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg';

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.clipStartTime;
    _localCropOffset = widget.cropOffsetX;
    _initIframe();
    _listenToMessages();
    _startLoopTicker();
  }

  void _initIframe() {
    _viewId = 'clip-preview-${widget.videoId}-${DateTime.now().microsecondsSinceEpoch}';
    if (!_registeredClipViews.contains(_viewId)) {
      _registeredClipViews.add(_viewId);
      final origin = html.window.location.origin;
      final isLocal = origin.contains('localhost') ||
          origin.contains('127.0.0.1') ||
          origin.isEmpty ||
          origin == 'null' ||
          !origin.startsWith('https://');
      final originParam = isLocal ? '' : '&origin=$origin';
      final startParam = '&start=${widget.clipStartTime.toInt()}';

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) {
          final iframe = html.IFrameElement()
            ..id = _viewId
            ..src =
                'https://www.youtube-nocookie.com/embed/${widget.videoId}?autoplay=1&mute=0&playsinline=1&controls=0&rel=0&modestbranding=1&enablejsapi=1$originParam$startParam'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow =
                'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
            ..referrerPolicy = 'strict-origin-when-cross-origin'
            ..allowFullscreen = false;
          _iframeElement = iframe;
          return iframe;
        },
      );
    }
  }

  void _listenToMessages() {
    _msgSub = html.window.onMessage.listen((event) {
      if (event.data is String) {
        try {
          final data = jsonDecode(event.data);
          if (data is Map && data['event'] == 'infoDelivery') {
            final info = data['info'];
            if (info is Map) {
              if (info.containsKey('currentTime')) {
                final curTime = (info['currentTime'] as num).toDouble();
                _currentPosition = curTime;
                widget.onPositionChanged?.call(curTime);

                if (curTime >= widget.clipEndTime || curTime < widget.clipStartTime - 1.0) {
                  if (widget.isLooping) {
                    seekTo(widget.clipStartTime);
                  } else {
                    pause();
                  }
                }
              }
              if (info.containsKey('playerState')) {
                final state = info['playerState'];
                // 1 = playing, 2 = paused, 0 = ended
                if (state == 1 && !_isPlaying) {
                  setState(() => _isPlaying = true);
                } else if ((state == 2 || state == 0) && _isPlaying) {
                  setState(() => _isPlaying = false);
                }
              }
            }
          }
        } catch (_) {}
      }
    });
  }

  void _startLoopTicker() {
    _loopTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_isPlaying) return;

      if (_currentPosition >= widget.clipEndTime) {
        if (widget.isLooping) {
          seekTo(widget.clipStartTime);
        } else {
          pause();
        }
      }
    });
  }

  void _sendIframeCommand(String func, [List<dynamic>? args]) {
    html.IFrameElement? targetIframe = _iframeElement;
    if (targetIframe == null || targetIframe.contentWindow == null) {
      try {
        final elem = html.document.getElementById(_viewId) ?? html.document.querySelector('iframe');
        if (elem is html.IFrameElement) {
          targetIframe = elem;
          _iframeElement = elem;
        }
      } catch (_) {}
    }
    if (targetIframe == null || targetIframe.contentWindow == null) return;
    try {
      final msg = jsonEncode({
        'event': 'command',
        'func': func,
        'args': args ?? [],
      });
      targetIframe.contentWindow!.postMessage(msg, '*');
    } catch (_) {}
  }

  void seekTo(double seconds) {
    _currentPosition = seconds.clamp(widget.clipStartTime, widget.clipEndTime);
    _sendIframeCommand('seekTo', [_currentPosition, true]);
    if (_isPlaying) {
      _sendIframeCommand('playVideo');
    }
    if (mounted) setState(() {});
  }

  void play() {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true;
      _showFeedback = true;
    });
    if (_currentPosition >= widget.clipEndTime) {
      seekTo(widget.clipStartTime);
    }
    _sendIframeCommand('playVideo');
    widget.onTogglePlayPause?.call();
    _triggerFeedbackTimer();
  }

  void pause() {
    if (!_isPlaying) return;
    setState(() {
      _isPlaying = false;
      _showFeedback = true;
    });
    _sendIframeCommand('pauseVideo');
    widget.onTogglePlayPause?.call();
    _triggerFeedbackTimer();
  }

  void togglePlayPause() {
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void _triggerFeedbackTimer() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showFeedback = false);
    });
  }

  @override
  void didUpdateWidget(covariant _WebClipPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDraggingCrop && oldWidget.cropOffsetX != widget.cropOffsetX) {
      _localCropOffset = widget.cropOffsetX;
    }
    if (oldWidget.clipStartTime != widget.clipStartTime) {
      if (_currentPosition < widget.clipStartTime ||
          _currentPosition > widget.clipEndTime) {
        seekTo(widget.clipStartTime);
      }
    }
    if (oldWidget.videoId != widget.videoId) {
      _initIframe();
    }
  }

  @override
  void dispose() {
    _loopTicker?.cancel();
    _msgSub?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  String _formatSeconds(double sec) {
    final totalSec = sec.toInt();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _getPanLabel() {
    if (_localCropOffset < -0.15) {
      return 'Left (${(_localCropOffset * 100).abs().toInt()}%)';
    } else if (_localCropOffset > 0.15) {
      return 'Right (${(_localCropOffset * 100).toInt()}%)';
    }
    return 'Center';
  }

  @override
  Widget build(BuildContext context) {
    final clipDuration = (widget.clipEndTime - widget.clipStartTime).clamp(1.0, 180.0);
    final elapsedInClip = (_currentPosition - widget.clipStartTime).clamp(0.0, clipDuration);
    final progressFraction = (elapsedInClip / clipDuration).clamp(0.0, 1.0);
    final is9x16 = widget.framingMode == ShortsFramingMode.portrait9x16;

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');

    Widget playerOrThumb = isTest
        ? Image.network(
            _thumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Colors.black),
          )
        : HtmlElementView(
            key: ValueKey(_viewId),
            viewType: _viewId,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double canvasHeight = 220.0;
        final double canvasWidth = constraints.maxWidth;
        final double cropBoxHeight = canvasHeight;
        final double cropBoxWidth = (cropBoxHeight * (9 / 16)).clamp(80.0, canvasWidth);
        final double travelDistance = (canvasWidth - cropBoxWidth).clamp(0.0, canvasWidth);
        final double cropBoxLeft = (travelDistance / 2) + (_localCropOffset * (travelDistance / 2));

        return Container(
          height: canvasHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Full 16:9 Landscape Live Video Canvas
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true, // Always let Flutter capture drag & click gestures smoothly
                    child: playerOrThumb,
                  ),
                ),

                // 2. Dimmed Outer Regions & Glowing 9:16 Viewfinder (in 9:16 mode)
                if (is9x16) ...[
                  // Dimmed Left Mask
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: cropBoxLeft.clamp(0.0, canvasWidth),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.68),
                    ),
                  ),

                  // Dimmed Right Mask
                  Positioned(
                    left: (cropBoxLeft + cropBoxWidth).clamp(0.0, canvasWidth),
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.68),
                    ),
                  ),

                  // Active 9:16 Viewfinder
                  Positioned(
                    left: cropBoxLeft.clamp(0.0, travelDistance),
                    top: 0,
                    bottom: 0,
                    width: cropBoxWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFF59E0B),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: _isDraggingCrop ? 0.55 : 0.3),
                            blurRadius: _isDraggingCrop ? 16 : 12,
                            spreadRadius: _isDraggingCrop ? 2 : 1,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Golden Corner Brackets
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                  left: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                  right: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                  left: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                  right: BorderSide(color: Color(0xFFF59E0B), width: 2),
                                ),
                              ),
                            ),
                          ),

                          // Center Drag Handle Badge
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.7),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.drag_indicator_rounded, color: Color(0xFFF59E0B), size: 13),
                                  const SizedBox(width: 2),
                                  Text(
                                    _getPanLabel(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // 3. Direct Drag & Tap GestureDetector with displacement discrimination
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: is9x16
                        ? (_) {
                            _dragDistance = 0.0;
                            setState(() {
                              _isDraggingCrop = true;
                            });
                          }
                        : null,
                    onHorizontalDragUpdate: is9x16
                        ? (details) {
                            _dragDistance += (details.primaryDelta ?? 0).abs();
                            final halfTravel = travelDistance / 2;
                            if (halfTravel > 0) {
                              final deltaNormalized = details.primaryDelta! / halfTravel;
                              final newOffset = (_localCropOffset + deltaNormalized).clamp(-1.0, 1.0);
                              setState(() {
                                _localCropOffset = newOffset;
                              });
                              widget.onCropOffsetChanged?.call(newOffset);
                            }
                          }
                        : null,
                    onHorizontalDragEnd: is9x16
                        ? (_) {
                            setState(() {
                              _isDraggingCrop = false;
                            });
                            if (_dragDistance < 8.0) {
                              togglePlayPause();
                            }
                          }
                        : null,
                    onHorizontalDragCancel: is9x16
                        ? () {
                            setState(() {
                              _isDraggingCrop = false;
                            });
                          }
                        : null,
                    onTap: is9x16 ? null : togglePlayPause,
                  ),
                ),

                // 4. Header Badges: LIVE PREVIEW & MODE INDICATOR
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.circle, color: Colors.white, size: 7),
                            SizedBox(width: 5),
                            Text(
                              'LIVE PREVIEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              is9x16 ? Icons.crop_portrait : Icons.stay_current_landscape,
                              color: const Color(0xFFF59E0B),
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              is9x16 ? '9:16 Short' : '16:9 Landscape',
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 5. Center Play / Pause Feedback & Tap Target
                Center(
                  child: AnimatedOpacity(
                    opacity: _showFeedback ? 1.0 : (_isPlaying ? 0.0 : 0.85),
                    duration: const Duration(milliseconds: 180),
                    child: GestureDetector(
                      onTap: togglePlayPause,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.65),
                          border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 38,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ),
                ),

                // 6. Bottom Interactive Clip Scrubber Bar & Play/Pause Button
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: togglePlayPause,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: const Color(0xFFF59E0B),
                                          size: 14,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _isPlaying ? 'Pause' : 'Play',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_formatSeconds(elapsedInClip)} / ${_formatSeconds(clipDuration)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            if (widget.isLooping) ...[
                              Row(
                                children: const [
                                  Icon(Icons.repeat, color: Color(0xFFF59E0B), size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'Looping',
                                    style: TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Draggable Interactive Scrubber Bar
                        LayoutBuilder(
                          builder: (context, barConstraints) {
                            final barWidth = barConstraints.maxWidth;
                            final double thumbLeft =
                                (progressFraction * (barWidth - 10)).clamp(0.0, barWidth - 10);

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                final localX = details.localPosition.dx;
                                final fraction = (localX / barWidth).clamp(0.0, 1.0);
                                seekTo(widget.clipStartTime + (fraction * clipDuration));
                              },
                              onTapDown: (details) {
                                final localX = details.localPosition.dx;
                                final fraction = (localX / barWidth).clamp(0.0, 1.0);
                                seekTo(widget.clipStartTime + (fraction * clipDuration));
                              },
                              child: SizedBox(
                                height: 18,
                                child: Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Container(
                                      height: 5,
                                      width: barWidth,
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    Container(
                                      height: 5,
                                      width: (progressFraction * barWidth).clamp(0.0, barWidth),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    Positioned(
                                      left: thumbLeft,
                                      child: Container(
                                        width: 10,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(3),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFF59E0B)
                                                  .withValues(alpha: 0.8),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
