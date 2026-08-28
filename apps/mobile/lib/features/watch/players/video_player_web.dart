// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

final Set<String> _registeredVideoViews = {};

void pausePlatformMainVideo() {
  try {
    final iframes = html.document.querySelectorAll('iframe');
    for (final elem in iframes) {
      if (elem is html.IFrameElement) {
        elem.contentWindow?.postMessage(
          '{"event":"command","func":"pauseVideo","args":""}',
          '*',
        );
      }
    }
  } catch (_) {}
}

Widget buildPlatformVideoPlayer({
  required String videoId,
  double? startSeconds,
  ValueChanged<Duration>? onPositionChanged,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _WebVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    onPositionChanged: onPositionChanged,
    builder: builder,
  );
}

class _WebVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final ValueChanged<Duration>? onPositionChanged;
  final Widget Function(BuildContext context, Widget player) builder;

  const _WebVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
    this.onPositionChanged,
    required this.builder,
  });

  @override
  State<_WebVideoPlayerWrapper> createState() => _WebVideoPlayerWrapperState();
}

class _WebVideoPlayerWrapperState extends State<_WebVideoPlayerWrapper> {
  late String _viewId;
  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    _initView();
    _listenToIframeEvents();
  }

  @override
  void didUpdateWidget(covariant _WebVideoPlayerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _initView();
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  void _listenToIframeEvents() {
    _msgSub = html.window.onMessage.listen((event) {
      try {
        if (event.data is String) {
          final data = jsonDecode(event.data);
          if (data is Map && data['event'] == 'infoDelivery') {
            final info = data['info'];
            if (info is Map && info['currentTime'] != null) {
              final sec = (info['currentTime'] as num).toDouble();
              final pos = Duration(milliseconds: (sec * 1000).toInt());
              widget.onPositionChanged?.call(pos);
            }
          }
        }
      } catch (_) {}
    });
  }

  void _initView() {
    _viewId = 'video-player-${widget.videoId}-${DateTime.now().millisecondsSinceEpoch}';
    if (!_registeredVideoViews.contains(_viewId)) {
      _registeredVideoViews.add(_viewId);
      final startParam = (widget.startSeconds != null && widget.startSeconds! > 0)
          ? '&start=${widget.startSeconds!.toInt()}'
          : '';

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) {
          final origin = html.window.location.origin;
          final iframe = html.IFrameElement()
            ..src =
                'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&mute=0&playsinline=1&controls=1&rel=0&modestbranding=1&enablejsapi=1&origin=$origin$startParam'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow =
                'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
            ..allowFullscreen = true;
          return iframe;
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerWidget = AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: HtmlElementView(viewType: _viewId),
      ),
    );

    return widget.builder(context, playerWidget);
  }
}
