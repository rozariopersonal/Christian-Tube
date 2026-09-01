import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/models/short.dart';

final Map<int, InAppWebViewController> _activeMobileSlots = {};

void stopAllPlatformShorts() {
  try {
    for (final controller in _activeMobileSlots.values) {
      controller.evaluateJavascript(
        source: "try { if (typeof pauseVideo === 'function') { pauseVideo(); } } catch(e) {}",
      );
    }
  } catch (_) {}
}

void pausePlatformShorts() {
  try {
    for (final controller in _activeMobileSlots.values) {
      controller.evaluateJavascript(
        source: "try { if (typeof pauseVideo === 'function') { pauseVideo(); } } catch(e) {}",
      );
    }
  } catch (_) {}
}

void resumePlatformShorts() {
  // Handled per active slot in didUpdateWidget
}

void seekPlatformShort(int slotIndex, double seconds) {
  try {
    final controller = _activeMobileSlots[slotIndex];
    controller?.evaluateJavascript(
      source: "try { if (typeof seekTo === 'function') { seekTo($seconds); } else if (typeof player !== 'undefined' && player && typeof player.seekTo === 'function') { player.seekTo($seconds, true); } } catch(e) {}",
    );
  } catch (_) {}
}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
  int slotIndex = 0,
  ValueChanged<int>? onStateChange,
  void Function(double current, double total)? onProgress,
}) {
  return _MobileShortsPlayerWidget(
    key: ValueKey('shorts_mobile_slot_${slotIndex}_${short.id}'),
    short: short,
    isPlaying: isPlaying,
    slotIndex: slotIndex,
    onStateChange: onStateChange,
    onProgress: onProgress,
  );
}

class _MobileShortsPlayerWidget extends StatefulWidget {
  final Short short;
  final bool isPlaying;
  final int slotIndex;
  final ValueChanged<int>? onStateChange;
  final void Function(double current, double total)? onProgress;

  const _MobileShortsPlayerWidget({
    super.key,
    required this.short,
    required this.isPlaying,
    this.slotIndex = 0,
    this.onStateChange,
    this.onProgress,
  });

  @override
  State<_MobileShortsPlayerWidget> createState() => _MobileShortsPlayerWidgetState();
}

class _MobileShortsPlayerWidgetState extends State<_MobileShortsPlayerWidget> {
  InAppWebViewController? _webViewController;

  @override
  void didUpdateWidget(covariant _MobileShortsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.short.playableVideoId != widget.short.playableVideoId) {
      _loadVideo(
        widget.short.playableVideoId,
        widget.short.playableStartSeconds,
        widget.short.playableEndSeconds,
      );
      if (widget.isPlaying) {
        _play();
      } else {
        _pause();
      }
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _play();
      } else {
        _pause();
      }
    }
  }

  void _loadVideo(String videoId, int startSeconds, int? endSeconds) {
    _webViewController?.evaluateJavascript(
      source: "try { if (typeof loadVideoById === 'function') { loadVideoById('$videoId', $startSeconds, ${endSeconds ?? 'null'}); } } catch(e) {}",
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
    if (_activeMobileSlots[widget.slotIndex] == _webViewController) {
      _activeMobileSlots.remove(widget.slotIndex);
    }
    super.dispose();
  }

  String _buildShortsPlayerHtml(
    String initialVideoId,
    int startSec,
    int? endSec,
    bool isClipped,
    double cropOffset,
  ) {
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
            width: ${isClipped ? 'calc(100vh * (16 / 9))' : '100%'};
            height: 100%;
            position: ${isClipped ? 'absolute' : 'relative'};
            top: 0;
            left: ${isClipped ? '50%' : '0'};
            transform: ${isClipped ? 'translateX(calc(-50% - ${(cropOffset * 50)}%))' : 'none'};
            pointer-events: none;
        }
        .ytp-chrome-top, .ytp-chrome-bottom, .ytp-watermark, .ytp-pause-overlay,
        .ytp-show-cards-title, .ytp-gradient-top, .ytp-gradient-bottom,
        .ytp-youtube-button, .ytp-contextmenu, .ytp-large-play-button {
            display: none !important;
            opacity: 0 !important;
            visibility: hidden !important;
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
        var pendingPlay = ${widget.isPlaying ? 'true' : 'false'};
        var pendingVideoId = '$initialVideoId';
        var clipStart = $startSec;
        var clipEnd = ${endSec ?? 'null'};
        var progressTicker = null;

        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                videoId: '$initialVideoId',
                playerVars: {
                    'autoplay': ${widget.isPlaying ? 1 : 0},
                    'controls': 0,
                    'playsinline': 1,
                    'enablejsapi': 1,
                    'fs': 0,
                    'rel': 0,
                    'start': $startSec,
                    ${endSec != null ? "'end': $endSec," : ''}
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
                            if (clipStart > 0) {
                                player.seekTo(clipStart, true);
                            }
                            if (pendingVideoId && pendingVideoId !== '$initialVideoId') {
                                player.loadVideoById({ videoId: pendingVideoId, startSeconds: clipStart, endSeconds: clipEnd });
                            } else if (pendingPlay) {
                                e.target.playVideo();
                            }
                            if (window.flutter_inappwebview) {
                                window.flutter_inappwebview.callHandler('onEngineReady');
                            }
                        } catch(err){}
                    },
                    'onStateChange': function(event) {
                        try {
                            // Auto-loop when video ends (state == 0)
                            if (event.data === 0 && player) {
                                player.seekTo(clipStart, true);
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

            if (!progressTicker) {
                progressTicker = setInterval(function() {
                    if (isReady && player && typeof player.getCurrentTime === 'function' && window.flutter_inappwebview) {
                        try {
                            var cur = player.getCurrentTime();
                            var dur = player.getDuration();

                            // Auto-loop when clip end boundary is reached
                            if (clipEnd !== null && clipEnd > 0 && cur >= (clipEnd - 0.25)) {
                                player.seekTo(clipStart, true);
                                player.playVideo();
                                cur = clipStart;
                            }

                            // Normalize timestamps for clipped sermons
                            if (clipStart > 0 || clipEnd !== null) {
                                var normalizedCur = Math.max(0, cur - clipStart);
                                var normalizedDur = (clipEnd !== null && clipEnd > clipStart) ? (clipEnd - clipStart) : Math.max(1, dur - clipStart);
                                window.flutter_inappwebview.callHandler('onProgress', normalizedCur, normalizedDur);
                            } else {
                                window.flutter_inappwebview.callHandler('onProgress', cur, dur);
                            }
                        } catch(e){}
                    }
                }, 250);
            }
        }

        function seekTo(sec) {
            if (isReady && player && typeof player.seekTo === 'function') {
                try {
                    var target = (clipStart > 0) ? (clipStart + sec) : sec;
                    player.seekTo(target, true);
                } catch(err){}
            }
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
            pendingPlay = true;
            if (isReady && player && typeof player.playVideo === 'function') {
                try {
                    player.playVideo();
                } catch(err){}
            }
        }

        function pauseVideo() {
            pendingPlay = false;
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
    return ClipRect(
      child: Container(
        color: Colors.black,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _buildShortsPlayerHtml(
              widget.short.playableVideoId,
              widget.short.playableStartSeconds,
              widget.short.playableEndSeconds,
              widget.short.isClippedSermon,
              widget.short.cropOffsetX.clamp(-1.0, 1.0),
            ),
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
            _activeMobileSlots[widget.slotIndex] = controller;

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
              handlerName: 'onProgress',
              callback: (args) {
                if (args.length >= 2) {
                  final cur = (args[0] as num).toDouble();
                  final dur = (args[1] as num).toDouble();
                  widget.onProgress?.call(cur, dur);
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
      ),
    );
  }
}
