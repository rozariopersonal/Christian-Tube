// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

final Set<String> _registeredVideoViews = {};

Widget buildPlatformVideoPlayer({
  required String videoId,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _WebVideoPlayerWrapper(
    videoId: videoId,
    builder: builder,
  );
}

class _WebVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final Widget Function(BuildContext context, Widget player) builder;

  const _WebVideoPlayerWrapper({
    required this.videoId,
    required this.builder,
  });

  @override
  State<_WebVideoPlayerWrapper> createState() => _WebVideoPlayerWrapperState();
}

class _WebVideoPlayerWrapperState extends State<_WebVideoPlayerWrapper> {
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _initView();
  }

  @override
  void didUpdateWidget(covariant _WebVideoPlayerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _initView();
    }
  }

  void _initView() {
    _viewId = 'video-player-${widget.videoId}-${DateTime.now().millisecondsSinceEpoch}';
    if (!_registeredVideoViews.contains(_viewId)) {
      _registeredVideoViews.add(_viewId);
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) {
          final iframe = html.IFrameElement()
            ..src =
                'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&mute=0&playsinline=1&controls=1&rel=0&modestbranding=1'
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
