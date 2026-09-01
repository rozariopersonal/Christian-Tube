import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/theme/app_tokens.dart';

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
  bool isFullScreen = false,
  VoidCallback? onToggleFullScreen,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return _MobileVideoPlayerWrapper(
    videoId: videoId,
    startSeconds: startSeconds,
    onPositionChanged: onPositionChanged,
    isFullScreen: isFullScreen,
    onToggleFullScreen: onToggleFullScreen,
    builder: builder,
  );
}

class _MobileVideoPlayerWrapper extends StatefulWidget {
  final String videoId;
  final double? startSeconds;
  final ValueChanged<Duration>? onPositionChanged;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final Widget Function(BuildContext context, Widget player) builder;

  const _MobileVideoPlayerWrapper({
    required this.videoId,
    this.startSeconds,
    this.onPositionChanged,
    this.isFullScreen = false,
    this.onToggleFullScreen,
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
    if (oldWidget.isFullScreen != widget.isFullScreen) {
      _applyFullscreenMode(widget.isFullScreen);
    }
  }

  /// App-level fullscreen: rotates to landscape + immersive system UI on entry,
  /// restores portrait + edge-to-edge on exit. Everything is Flutter state so
  /// it can never get stuck (the broken platform WebView fullscreen path is
  /// disabled via `fs=0` / stripped `allowfullscreen` in the embed HTML).
  void _applyFullscreenMode(bool full) {
    if (full) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        }
      });
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
                    'fs': 0,
                    'rel': 0,
                    'modestbranding': 1,
                    'origin': 'https://www.youtube-nocookie.com',
                    'start': $startSec
                },
                events: {
                    'onReady': function(e) {
                        try {
                            // Block YouTube's native (platform) fullscreen: in a
                            // WebView it renders a broken half-black/half-white
                            // screen and cannot be exited. Fullscreen is handled
                            // by the Flutter overlay toggle instead.
                            var ifr = e.target.getIframe();
                            if (ifr) {
                                ifr.removeAttribute('allowfullscreen');
                                ifr.setAttribute('donotallowfullscreen', '');
                            }
                            e.target.playVideo();
                        } catch(err){}
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
    if (InAppWebViewPlatform.instance == null) {
      return widget.builder(
        context,
        Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
          ),
        ),
      );
    }

    final webView = Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InAppWebView(
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
              // Safety net only: native WebView fullscreen is disabled in the
              // embed HTML (`fs=0`, `allowfullscreen` stripped), so this should
              // never fire. Kept to avoid leaving the device in a broken state.
              _applyFullscreenMode(true);
            },
            onExitFullscreen: (controller) {
              _applyFullscreenMode(false);
            },
          ),
          // Flutter-supported fullscreen toggle. The native YouTube fullscreen
          // control is hidden (`fs=0`); this rotates the player to landscape /
          // fills the window and is always exit-able in-app.
          if (widget.onToggleFullScreen != null)
            _buildFullScreenButton(context),
        ],
      ),
    );

    // The player element type and depth are kept identical in every mode so the
    // underlying WebView is never torn down on rotation / fullscreen toggle
    // (which would restart the video). The parent positions and sizes it.
    final playerWidget = SizedBox.expand(child: webView);

    return widget.builder(context, playerWidget);
  }

  Widget _buildFullScreenButton(BuildContext context) {
    return Positioned(
      right: 10,
      top: 10,
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
