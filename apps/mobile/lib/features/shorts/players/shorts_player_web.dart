// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

final Set<String> _registeredViews = {};

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
}) {
  return _WebShortsPlayerWidget(
    short: short,
    isPlaying: isPlaying,
  );
}

class _WebShortsPlayerWidget extends StatefulWidget {
  final Short short;
  final bool isPlaying;

  const _WebShortsPlayerWidget({
    required this.short,
    required this.isPlaying,
  });

  @override
  State<_WebShortsPlayerWidget> createState() => _WebShortsPlayerWidgetState();
}

class _WebShortsPlayerWidgetState extends State<_WebShortsPlayerWidget> {
  late String _viewId;
  html.IFrameElement? _iframeElement;

  @override
  void initState() {
    super.initState();
    _viewId = 'shorts-player-${widget.short.id}-${DateTime.now().millisecondsSinceEpoch}';

    if (!_registeredViews.contains(_viewId)) {
      _registeredViews.add(_viewId);
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src =
                'https://www.youtube.com/embed/${widget.short.id}?autoplay=${widget.isPlaying ? 1 : 0}&mute=0&loop=1&playlist=${widget.short.id}&playsinline=1&controls=1&rel=0&modestbranding=1'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow =
                'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
            ..allowFullscreen = true;

          _iframeElement = iframe;
          return iframe;
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant _WebShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying && _iframeElement != null) {
      // Send postMessage to YouTube IFrame API to play/pause
      final command = widget.isPlaying
          ? '{"event":"command","func":"playVideo","args":""}'
          : '{"event":"command","func":"pauseVideo","args":""}';
      _iframeElement?.contentWindow?.postMessage(command, '*');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: HtmlElementView(viewType: _viewId),
        ),
      ),
    );
  }
}
