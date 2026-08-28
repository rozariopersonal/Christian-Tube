import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

InAppWebViewController? _activeMainWebViewController;

void pausePlatformMainVideo() {
  try {
    _activeMainWebViewController?.evaluateJavascript(
      source: "try { if (typeof pauseVideo === 'function') { pauseVideo(); } } catch(e) {}",
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
    final startSec = (startSeconds != null && startSeconds > 0) ? startSeconds.toInt() : 0;
    _webViewController?.evaluateJavascript(
      source: "try { loadVideoById('$videoId', $startSec); } catch(e) {}",
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

  String _buildPlayerHtml(String videoId, double? startSeconds) {
    final startSec = (startSeconds != null && startSeconds > 0) ? startSeconds.toInt() : 0;
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        html, body {
            margin: 0;
            padding: 0;
            background-color: #000000;
            overflow: hidden;
            height: 100%;
            width: 100%;
        }
        #player {
            width: 100%;
            height: 100%;
            position: absolute;
            top: 0;
            left: 0;
        }
    </style>
</head>
<body>
    <div id="player"></div>
    <script>
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
        var player;
        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                videoId: '$videoId',
                playerVars: {
                    'autoplay': 1,
                    'controls': 1,
                    'playsinline': 1,
                    'enablejsapi': 1,
                    'fs': 1,
                    'rel': 0,
                    'modestbranding': 1,
                    'origin': 'https://www.youtube-nocookie.com',
                    'start': $startSec
                },
                events: {
                    'onReady': function(e) {
                        try { e.target.playVideo(); } catch(err){}
                    },
                    'onStateChange': function(event) {
                        try {
                            if (window.flutter_inappwebview) {
                                window.flutter_inappwebview.callHandler('onStateChange', event.data);
                            }
                        } catch(err){}
                    }
                }
            });
            setInterval(function() {
                try {
                    if (player && typeof player.getCurrentTime === 'function' && window.flutter_inappwebview) {
                        window.flutter_inappwebview.callHandler('onTimeUpdate', player.getCurrentTime());
                    }
                } catch(err){}
            }, 500);
        }
        function loadVideoById(id, startSec) {
            try {
                if (player && typeof player.loadVideoById === 'function') {
                    player.loadVideoById({ videoId: id, startSeconds: startSec || 0 });
                }
            } catch(err){}
        }
        function pauseVideo() {
            try {
                if (player && typeof player.pauseVideo === 'function') {
                    player.pauseVideo();
                }
            } catch(err){}
        }
    </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final playerWidget = AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _buildPlayerHtml(widget.videoId, widget.startSeconds),
            encoding: 'utf-8',
            baseUrl: WebUri.uri(Uri.https('www.youtube-nocookie.com')),
            mimeType: 'text/html',
          ),
          initialSettings: InAppWebViewSettings(
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useHybridComposition: true,
            transparentBackground: false,
            supportZoom: false,
            allowsPictureInPictureMediaPlayback: true,
            userAgent: 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.0.0 Mobile Safari/537.36',
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
