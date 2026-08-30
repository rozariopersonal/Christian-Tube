// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

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
  bool isFullScreen = false,
  VoidCallback? onToggleFullScreen,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _WebVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    onPositionChanged: onPositionChanged,
    isFullScreen: isFullScreen,
    onToggleFullScreen: onToggleFullScreen,
    builder: builder,
  );
}

class _WebVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final ValueChanged<Duration>? onPositionChanged;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final Widget Function(BuildContext context, Widget player) builder;

  const _WebVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
    this.onPositionChanged,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    required this.builder,
  });

  @override
  State<_WebVideoPlayerWrapper> createState() => _WebVideoPlayerWrapperState();
}

class _WebVideoPlayerWrapperState extends State<_WebVideoPlayerWrapper> {
  late String _viewId;
  StreamSubscription? _msgSub;
  StreamSubscription? _fullScreenSub;

  @override
  void initState() {
    super.initState();
    _initView();
    _listenToIframeEvents();
    _watchForStrayNativeFullscreen();
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
    _fullScreenSub?.cancel();
    super.dispose();
  }

  /// Safety net: the native (browser) fullscreen of an iframe nested inside a
  /// Flutter `HtmlElementView` platform view breaks rendering (half black /
  /// half white) and cannot be exited, so it must never be entered. Native
  /// fullscreen is disabled on the iframe itself (`allowFullscreen=false`,
  /// `fs=0`); if anything still forces the document into fullscreen (e.g. a
  /// stray double-tap path in the player), immediately bail out of it.
  void _watchForStrayNativeFullscreen() {
    _fullScreenSub = html.document.onFullscreenChange.listen((_) {
      try {
        if (html.document.fullscreenElement != null) {
          html.document.exitFullscreen();
        }
      } catch (_) {}
    });
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
                'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&mute=0&playsinline=1&controls=1&rel=0&modestbranding=1&fs=0&enablejsapi=1&origin=$origin$startParam'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow =
                'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
            // Native iframe fullscreen inside a Flutter HtmlElementView renders
            // a corrupt half-black/half-white screen and is impossible to exit.
            ..allowFullscreen = false;
          return iframe;
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    final container = Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          HtmlElementView(viewType: _viewId),
          // Flutter-supported fullscreen toggle. The native YouTube fullscreen
          // button is hidden (`fs=0`); this app-level toggle enlarges the
          // player to fill the window and is always exit-able in-app.
          if (widget.onToggleFullScreen != null)
            _buildFullScreenButton(context),
        ],
      ),
    );

    final playerWidget = (isLandscape || widget.isFullScreen)
        ? SizedBox.expand(child: container)
        : AspectRatio(
            aspectRatio: 16 / 9,
            child: container,
          );

    return widget.builder(context, playerWidget);
  }

  Widget _buildFullScreenButton(BuildContext context) {
    return Positioned(
      right: 10,
      bottom: 10,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('video_fullscreen_toggle'),
          onTap: () => widget.onToggleFullScreen?.call(),
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.tokens.scrim.withValues(alpha: 0.62),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
            child: Icon(
              widget.isFullScreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}
