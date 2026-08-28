import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

InAppWebViewController? _activeMainWebViewController;

void pausePlatformMainVideo() {
  try {
    _activeMainWebViewController?.evaluateJavascript(
      source: "try { document.querySelector('iframe').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"pauseVideo\",\"args\":\"\"}', '*'); } catch(e) {}",
    );
  } catch (_) {}
}

Widget buildPlatformVideoPlayer({
  required String videoId,
  double? startSeconds,
  ValueChanged<Duration>? onPositionChanged,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _MobileVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    onPositionChanged: onPositionChanged,
    builder: builder,
  );
}

class _MobileVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final ValueChanged<Duration>? onPositionChanged;
  final Widget Function(BuildContext context, Widget player) builder;

  const _MobileVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
    this.onPositionChanged,
    required this.builder,
  });

  @override
  State<_MobileVideoPlayerWrapper> createState() =>
      _MobileVideoPlayerWrapperState();
}

class _MobileVideoPlayerWrapperState extends State<_MobileVideoPlayerWrapper> {
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    // Allow sensor auto-rotation while on video player screen
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void didUpdateWidget(covariant _MobileVideoPlayerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _loadVideo(widget.videoId, widget.startSeconds);
    }
  }

  void _loadVideo(String videoId, double? startSeconds) {
    final startParam = (startSeconds != null && startSeconds > 0)
        ? '&start=${startSeconds.toInt()}'
        : '';
    final url =
        'https://www.youtube.com/embed/$videoId?autoplay=1&mute=0&playsinline=1&controls=1&rel=0&modestbranding=1&enablejsapi=1$startParam';
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  @override
  void dispose() {
    if (_activeMainWebViewController == _webViewController) {
      _activeMainWebViewController = null;
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  String _buildInitialUrl() {
    final startParam = (widget.startSeconds != null && widget.startSeconds! > 0)
        ? '&start=${widget.startSeconds!.toInt()}'
        : '';
    return 'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&mute=0&playsinline=1&controls=1&rel=0&modestbranding=1&enablejsapi=1$startParam';
  }

  @override
  Widget build(BuildContext context) {
    final playerWidget = AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(_buildInitialUrl()),
          ),
          initialSettings: InAppWebViewSettings(
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useHybridComposition: true,
            transparentBackground: false,
            supportZoom: false,
            allowsPictureInPictureMediaPlayback: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
            _activeMainWebViewController = controller;
            controller.addJavaScriptHandler(
              handlerName: 'onTimeUpdate',
              callback: (args) {
                if (args.isNotEmpty && args[0] is num) {
                  final sec = (args[0] as num).toDouble();
                  widget.onPositionChanged
                      ?.call(Duration(milliseconds: (sec * 1000).toInt()));
                }
              },
            );
          },
          onLoadStop: (controller, url) {
            controller.evaluateJavascript(source: """
              window.addEventListener('message', function(event) {
                try {
                  var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
                  if (data && data.event === 'infoDelivery' && data.info && data.info.currentTime) {
                    window.flutter_inappwebview.callHandler('onTimeUpdate', data.info.currentTime);
                  }
                } catch(e) {}
              });
            """);
          },
          onEnterFullscreen: (controller) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          },
          onExitFullscreen: (controller) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ]);
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              }
            });
          },
        ),
      ),
    );

    return widget.builder(context, playerWidget);
  }
}
