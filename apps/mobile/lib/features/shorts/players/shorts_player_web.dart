// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
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
  bool _isPaused = false;
  bool _showFeedback = false;
  Timer? _feedbackTimer;

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

  void _togglePlayPause() {
    if (_iframeElement == null) return;
    if (_isPaused) {
      _iframeElement?.contentWindow?.postMessage(
        '{"event":"command","func":"playVideo","args":""}',
        '*',
      );
      _isPaused = false;
    } else {
      _iframeElement?.contentWindow?.postMessage(
        '{"event":"command","func":"pauseVideo","args":""}',
        '*',
      );
      _isPaused = true;
    }

    setState(() {
      _showFeedback = true;
    });

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showFeedback = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant _WebShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _isPaused = false;
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
    _feedbackTimer?.cancel();
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              HtmlElementView(
                key: ValueKey(_viewId),
                viewType: _viewId!,
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _togglePlayPause,
                child: const SizedBox.expand(),
              ),
              Center(
                child: AnimatedOpacity(
                  opacity: _showFeedback ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                    child: Icon(
                      !_isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 54,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
