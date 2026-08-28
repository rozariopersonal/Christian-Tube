import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/models/short.dart';

InAppWebViewController? _activeShortsWebViewController;

void stopAllPlatformShorts() {
  try {
    _activeShortsWebViewController?.evaluateJavascript(
      source: "try { if (typeof pauseVideo === 'function') { pauseVideo(); } } catch(e) {}",
    );
  } catch (_) {}
}

void pausePlatformShorts() {
  try {
    _activeShortsWebViewController?.evaluateJavascript(
      source: "try { if (typeof pauseVideo === 'function') { pauseVideo(); } } catch(e) {}",
    );
  } catch (_) {}
}

void resumePlatformShorts() {
  try {
    _activeShortsWebViewController?.evaluateJavascript(
      source: "try { if (typeof playVideo === 'function') { playVideo(); } } catch(e) {}",
    );
  } catch (_) {}
}

void loadPlatformShort(String videoId) {
  try {
    _activeShortsWebViewController?.evaluateJavascript(
      source: "try { if (typeof loadVideoById === 'function') { loadVideoById('$videoId'); } } catch(e) {}",
    );
  } catch (_) {}
}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
  ValueChanged<int>? onStateChange,
}) {
  return _MobileShortsPlayerWidget(
    short: short,
    isPlaying: isPlaying,
    onStateChange: onStateChange,
  );
}

class _MobileShortsPlayerWidget extends StatefulWidget {
  final Short short;
  final bool isPlaying;
  final ValueChanged<int>? onStateChange;

  const _MobileShortsPlayerWidget({
    required this.short,
    required this.isPlaying,
    this.onStateChange,
  });

  @override
  State<_MobileShortsPlayerWidget> createState() => _MobileShortsPlayerWidgetState();
}

class _MobileShortsPlayerWidgetState extends State<_MobileShortsPlayerWidget> {
  InAppWebViewController? _webViewController;

  @override
  void didUpdateWidget(covariant _MobileShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.short.id != widget.short.id) {
      _loadVideo(widget.short.id);
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _play();
      } else {
        _pause();
      }
    }
  }

  void _loadVideo(String videoId) {
    _webViewController?.evaluateJavascript(
      source: "try { if (typeof loadVideoById === 'function') { loadVideoById('$videoId'); } } catch(e) {}",
    );
  }

  void _play() {
    _webViewController?.evaluateJavascript(
      source: "try { if (typeof playVideo === 'function') { playVideo(); } } catch(e) {}",
    );
  }

  void _pause() {
    _webViewController?.evaluateJavascript(
      source: "try { if (typeof pauseVideo === 'function') { pauseVideo(); } } catch(e) {}",
    );
  }

  @override
  void dispose() {
    if (_activeShortsWebViewController == _webViewController) {
      _activeShortsWebViewController = null;
    }
    super.dispose();
  }

  String _buildShortsPlayerHtml(String initialVideoId) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            -webkit-user-select: none;
            user-select: none;
        }
        html, body {
            background-color: #000000;
            overflow: hidden;
            height: 100%;
            width: 100%;
        }
        #player-container {
            width: 100vw;
            height: 100vh;
            position: absolute;
            top: 0;
            left: 0;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #player {
            width: 100%;
            height: 100%;
            pointer-events: none;
        }
        /* Strip YouTube branding & top/bottom chrome overlays */
        .ytp-chrome-top, .ytp-chrome-bottom, .ytp-watermark, .ytp-pause-overlay,
        .ytp-show-cards-title, .ytp-gradient-top, .ytp-gradient-bottom,
        .ytp-youtube-button, .ytp-contextmenu {
            display: none !important;
            opacity: 0 !important;
            pointer-events: none !important;
        }
    </style>
</head>
<body>
    <div id="player-container">
        <div id="player"></div>
    </div>
    <script>
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
        
        var player;
        var isReady = false;
        var pendingVideoId = '$initialVideoId';

        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                videoId: '$initialVideoId',
                playerVars: {
                    'autoplay': 1,
                    'controls': 0,
                    'playsinline': 1,
                    'enablejsapi': 1,
                    'fs': 0,
                    'rel': 0,
                    'modestbranding': 1,
                    'iv_load_policy': 3,
                    'disablekb': 1,
                    'origin': 'https://www.youtube-nocookie.com',
                    'mute': 0
                },
                events: {
                    'onReady': function(e) {
                        isReady = true;
                        try {
                            if (pendingVideoId && pendingVideoId !== '$initialVideoId') {
                                player.loadVideoById({ videoId: pendingVideoId, startSeconds: 0 });
                            } else {
                                e.target.playVideo();
                            }
                            if (window.flutter_inappwebview) {
                                window.flutter_inappwebview.callHandler('onEngineReady');
                            }
                        } catch(err){}
                    },
                    'onStateChange': function(event) {
                        try {
                            // Loop automatically when video ends (state == 0)
                            if (event.data === 0 && player) {
                                player.seekTo(0);
                                player.playVideo();
                            }
                            if (window.flutter_inappwebview) {
                                window.flutter_inappwebview.callHandler('onStateChange', event.data);
                            }
                        } catch(err){}
                    },
                    'onError': function(event) {
                        try {
                            if (window.flutter_inappwebview) {
                                window.flutter_inappwebview.callHandler('onError', event.data);
                            }
                        } catch(err){}
                    }
                }
            });
        }

        function loadVideoById(id) {
            pendingVideoId = id;
            if (isReady && player && typeof player.loadVideoById === 'function') {
                try {
                    player.loadVideoById({ videoId: id, startSeconds: 0 });
                } catch(err){}
            }
        }

        function playVideo() {
            if (isReady && player && typeof player.playVideo === 'function') {
                try {
                    player.playVideo();
                } catch(err){}
            }
        }

        function pauseVideo() {
            if (isReady && player && typeof player.pauseVideo === 'function') {
                try {
                    player.pauseVideo();
                } catch(err){}
            }
        }
    </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _buildShortsPlayerHtml(widget.short.id),
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
          allowsPictureInPictureMediaPlayback: false,
          verticalScrollBarEnabled: false,
          horizontalScrollBarEnabled: false,
          disableHorizontalScroll: true,
          disableVerticalScroll: true,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          _activeShortsWebViewController = controller;

          controller.addJavaScriptHandler(
            handlerName: 'onStateChange',
            callback: (args) {
              if (args.isNotEmpty && args[0] is int) {
                final state = args[0] as int;
                widget.onStateChange?.call(state);
              }
            },
          );

          controller.addJavaScriptHandler(
            handlerName: 'onEngineReady',
            callback: (_) {
              if (widget.isPlaying) {
                _play();
              }
            },
          );
        },
      ),
    );
  }
}
