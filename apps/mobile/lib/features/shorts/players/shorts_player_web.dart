// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

final Map<int, html.IFrameElement> _activeWebSlots = {};
final Set<String> _registeredSlotViews = {};

void stopAllPlatformShorts() {
  try {
    for (final iframe in _activeWebSlots.values) {
      iframe.contentWindow?.postMessage(
        '{"event":"command","func":"pauseVideo","args":""}',
        '*',
      );
      iframe.contentWindow?.postMessage(
        '{"event":"command","func":"stopVideo","args":""}',
        '*',
      );
    }
  } catch (_) {}
}

void pausePlatformShorts() {
  try {
    for (final iframe in _activeWebSlots.values) {
      iframe.contentWindow?.postMessage(
        '{"event":"command","func":"pauseVideo","args":""}',
        '*',
      );
    }
  } catch (_) {}
}

void resumePlatformShorts() {
  // Resumed per active slot in didUpdateWidget
}

void seekPlatformShort(int slotIndex, double seconds) {
  try {
    final iframe = _activeWebSlots[slotIndex];
    iframe?.contentWindow?.postMessage(
      jsonEncode({
        'event': 'command',
        'func': 'seekTo',
        'args': [seconds, true],
      }),
      '*',
    );
  } catch (_) {}
}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
  int slotIndex = 0,
  ValueChanged<int>? onStateChange,
  void Function(double current, double total)? onProgress,
}) {
  return _WebShortsPlayerWidget(
    key: ValueKey('shorts_web_slot_${slotIndex}_${short.id}'),
    short: short,
    isPlaying: isPlaying,
    slotIndex: slotIndex,
    onStateChange: onStateChange,
    onProgress: onProgress,
  );
}

class _WebShortsPlayerWidget extends StatefulWidget {
  final Short short;
  final bool isPlaying;
  final int slotIndex;
  final ValueChanged<int>? onStateChange;
  final void Function(double current, double total)? onProgress;

  const _WebShortsPlayerWidget({
    super.key,
    required this.short,
    required this.isPlaying,
    this.slotIndex = 0,
    this.onStateChange,
    this.onProgress,
  });

  @override
  State<_WebShortsPlayerWidget> createState() => _WebShortsPlayerWidgetState();
}

class _WebShortsPlayerWidgetState extends State<_WebShortsPlayerWidget> {
  late String _viewId;
  html.IFrameElement? _iframeElement;
  StreamSubscription? _msgSub;
  Timer? _autoplayTimer;

  @override
  void initState() {
    super.initState();
    _setupView();
    _listenToMessages();
    _scheduleAutoplay();
  }

  void _setupView() {
    final videoId = widget.short.playableVideoId;
    final startSec = widget.short.playableStartSeconds;
    final endSec = widget.short.playableEndSeconds;
    final startParam = startSec > 0 ? '&start=$startSec' : '';
    final endParam = endSec != null ? '&end=$endSec' : '';

    _viewId = 'shorts-slot-${widget.slotIndex}-$videoId';

    if (!_registeredSlotViews.contains(_viewId)) {
      _registeredSlotViews.add(_viewId);
      final origin = html.window.location.origin;
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) {
          final isClipped = widget.short.isClippedSermon;
          final cropOffset = widget.short.cropOffsetX.clamp(-1.0, 1.0);
          final offsetPercent = cropOffset * 50;

          final iframe = html.IFrameElement()
            ..id = _viewId
            ..src =
                'https://www.youtube.com/embed/$videoId?autoplay=1&mute=0&loop=1&playlist=$videoId&playsinline=1&controls=0&rel=0&modestbranding=1&enablejsapi=1$startParam$endParam&origin=$origin'
            ..style.border = 'none'
            ..style.position = isClipped ? 'absolute' : 'relative'
            ..style.top = '0'
            ..style.left = isClipped ? '50%' : '0'
            ..style.width = isClipped ? 'calc(100vh * (16 / 9))' : '100%'
            ..style.height = '100%'
            ..style.maxWidth = 'none'
            ..style.transform = isClipped
                ? 'translateX(calc(-50% - $offsetPercent%))'
                : 'none'
            ..style.pointerEvents = 'none'
            ..allow =
                'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
            ..allowFullscreen = false;

          _iframeElement = iframe;
          _activeWebSlots[widget.slotIndex] = iframe;
          return iframe;
        },
      );
    }
  }

  void _scheduleAutoplay() {
    if (!widget.isPlaying) return;
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && widget.isPlaying) {
        if (widget.short.playableStartSeconds > 0) {
          _sendIframeCommand('seekTo', [widget.short.playableStartSeconds, true]);
        }
        _sendIframeCommand('playVideo');
      }
    });
  }

  void _listenToMessages() {
    _msgSub = html.window.onMessage.listen((event) {
      if (event.data is String) {
        try {
          final data = jsonDecode(event.data);
          if (data is Map) {
            final eventType = data['event'];
            if (eventType == 'onReady' || eventType == 'initialDelivery') {
              if (widget.short.playableStartSeconds > 0) {
                _sendIframeCommand('seekTo', [widget.short.playableStartSeconds, true]);
              }
              if (widget.isPlaying) {
                _sendIframeCommand('playVideo');
              }
            } else if (eventType == 'infoDelivery') {
              final info = data['info'];
              if (info is Map) {
                if (info.containsKey('playerState')) {
                  final state = info['playerState'] as int;
                  widget.onStateChange?.call(state);

                  // Auto-loop when video finishes (state == 0)
                  if (state == 0 && widget.isPlaying) {
                    _sendIframeCommand('seekTo', [widget.short.playableStartSeconds, true]);
                    _sendIframeCommand('playVideo');
                  }
                }
                if (info.containsKey('currentTime')) {
                  final cur = (info['currentTime'] as num).toDouble();
                  final dur = info.containsKey('duration')
                      ? (info['duration'] as num).toDouble()
                      : 0.0;
                  widget.onProgress?.call(cur, dur);
                }
              }
            }
          }
        } catch (_) {}
      }
    });
  }

  void _sendIframeCommand(String func, [List<dynamic>? args]) {
    html.IFrameElement? targetIframe = _iframeElement;
    if (targetIframe == null || targetIframe.contentWindow == null) {
      try {
        final elem = html.document.getElementById(_viewId) ??
            _activeWebSlots[widget.slotIndex];
        if (elem is html.IFrameElement) {
          targetIframe = elem;
          _iframeElement = elem;
        }
      } catch (_) {}
    }
    if (targetIframe == null || targetIframe.contentWindow == null) {
      return;
    }
    try {
      final msg = jsonEncode({
        'event': 'command',
        'func': func,
        'args': args ?? [],
      });
      targetIframe.contentWindow!.postMessage(msg, '*');
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _WebShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.short.playableVideoId != widget.short.playableVideoId) {
      _sendIframeCommand('loadVideoById', [
        {
          'videoId': widget.short.playableVideoId,
          'startSeconds': widget.short.playableStartSeconds,
          if (widget.short.playableEndSeconds != null)
            'endSeconds': widget.short.playableEndSeconds,
        }
      ]);
      if (widget.isPlaying) {
        _sendIframeCommand('playVideo');
      } else {
        _sendIframeCommand('pauseVideo');
      }
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _sendIframeCommand('playVideo');
      } else {
        _sendIframeCommand('pauseVideo');
      }
    }
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _msgSub?.cancel();
    if (_activeWebSlots[widget.slotIndex] == _iframeElement) {
      _activeWebSlots.remove(widget.slotIndex);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        color: Colors.black,
        child: Center(
          child: HtmlElementView(
            key: ValueKey(_viewId),
            viewType: _viewId,
          ),
        ),
      ),
    );
  }
}
