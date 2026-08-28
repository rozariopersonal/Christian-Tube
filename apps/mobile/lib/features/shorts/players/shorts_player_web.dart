// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

html.IFrameElement? _activeWebShortsIframe;

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
    _activeWebShortsIframe = null;
  } catch (_) {}
}

void pausePlatformShorts() {
  try {
    _activeWebShortsIframe?.contentWindow?.postMessage(
      '{"event":"command","func":"pauseVideo","args":""}',
      '*',
    );
  } catch (_) {}
}

void resumePlatformShorts() {
  try {
    _activeWebShortsIframe?.contentWindow?.postMessage(
      '{"event":"command","func":"playVideo","args":""}',
      '*',
    );
  } catch (_) {}
}

void loadPlatformShort(String videoId) {
  try {
    _activeWebShortsIframe?.contentWindow?.postMessage(
      '{"event":"command","func":"loadVideoById","args":["$videoId",0]}',
      '*',
    );
  } catch (_) {}
}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
  ValueChanged<int>? onStateChange,
}) {
  return _WebShortsPlayerWidget(
    short: short,
    isPlaying: isPlaying,
    onStateChange: onStateChange,
  );
}

class _WebShortsPlayerWidget extends StatefulWidget {
  final Short short;
  final bool isPlaying;
  final ValueChanged<int>? onStateChange;

  const _WebShortsPlayerWidget({
    required this.short,
    required this.isPlaying,
    this.onStateChange,
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
    _setupView();
  }

  void _setupView() {
    final newId =
        'shorts-player-${widget.short.id}-${DateTime.now().microsecondsSinceEpoch}';
    _viewId = newId;

    ui_web.platformViewRegistry.registerViewFactory(
      newId,
      (int viewId) {
        final origin = html.window.location.origin;
        final iframe = html.IFrameElement()
          ..src =
              'https://www.youtube.com/embed/${widget.short.id}?autoplay=1&mute=0&loop=1&playlist=${widget.short.id}&playsinline=1&controls=0&rel=0&modestbranding=1&enablejsapi=1&origin=$origin'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow =
              'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
          ..allowFullscreen = true;

        _iframeElement = iframe;
        _activeWebShortsIframe = iframe;
        return iframe;
      },
    );

    // Trigger state change after a brief delay for web
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        widget.onStateChange?.call(1); // PLAYING
      }
    });
  }

  @override
  void didUpdateWidget(covariant _WebShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.short.id != widget.short.id) {
      loadPlatformShort(widget.short.id);
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        resumePlatformShorts();
      } else {
        pausePlatformShorts();
      }
    }
  }

  @override
  void dispose() {
    if (_activeWebShortsIframe == _iframeElement) {
      _activeWebShortsIframe = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_viewId == null) {
      return Container(color: Colors.black);
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: HtmlElementView(
          key: ValueKey(_viewId),
          viewType: _viewId!,
        ),
      ),
    );
  }
}
