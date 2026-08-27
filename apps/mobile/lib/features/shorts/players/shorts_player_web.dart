// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

void stopAllPlatformShorts() {
  try {
    final iframes = html.document.querySelectorAll('iframe');
    for (final elem in iframes) {
      if (elem is html.IFrameElement) {
        elem.contentWindow?.postMessage(
          '{"event":"command","func":"pauseVideo","args":""}',
          '*',
        );
        elem.contentWindow?.postMessage(
          '{"event":"command","func":"stopVideo","args":""}',
          '*',
        );
        elem.src = 'about:blank';
        elem.remove();
      }
    }
  } catch (_) {}
}

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
  String? _viewId;
  html.IFrameElement? _iframeElement;

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) {
      _setupView();
    }
  }

  void _setupView() {
    final newId =
        'shorts-player-${widget.short.id}-${DateTime.now().microsecondsSinceEpoch}';
    _viewId = newId;

    ui_web.platformViewRegistry.registerViewFactory(
      newId,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src =
              'https://www.youtube.com/embed/${widget.short.id}?autoplay=1&mute=0&loop=1&playlist=${widget.short.id}&playsinline=1&controls=1&rel=0&modestbranding=1&enablejsapi=1'
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

  void _killIframe() {
    try {
      _iframeElement?.contentWindow?.postMessage(
        '{"event":"command","func":"pauseVideo","args":""}',
        '*',
      );
      _iframeElement?.contentWindow?.postMessage(
        '{"event":"command","func":"stopVideo","args":""}',
        '*',
      );
      _iframeElement?.src = 'about:blank';
      _iframeElement?.remove();
      _iframeElement = null;
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _WebShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _setupView();
        setState(() {});
      } else {
        _killIframe();
        setState(() {
          _viewId = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _killIframe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPlaying || _viewId == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.short.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.black87),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 64,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: HtmlElementView(
            key: ValueKey(_viewId),
            viewType: _viewId!,
          ),
        ),
      ),
    );
  }
}
