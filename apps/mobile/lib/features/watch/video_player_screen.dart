import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/link/deep_link_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/services/user_sync_service.dart';
import '../../core/models/video.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/recommendation_video_card.dart';
import '../../shared/ui/video_options_bottom_sheet.dart';
import '../channels/channel_service.dart';
import '../channels/channel_detail_screen.dart';
import '../profile/user_service.dart';
import '../../core/config/app_config.dart';
import 'widgets/youtube_playlist_widget.dart';
import 'players/universal_video_player.dart';
import 'widgets/shorts_trimmer_sheet.dart';
import 'widgets/video_action_bar.dart';
import '../../core/models/short.dart';
import '../audio/controllers/audio_player_controller.dart';
import '../audio/models/audio_track.dart';
import '../audio/services/audio_catalog_service.dart';
import '../audio/widgets/full_audio_player_sheet.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final Video? initialVideo;
  final List<Video>? playlist;
  final String? playlistTitle;
  final int initialPlaylistIndex;
  final double? startSeconds;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    this.initialVideo,
    this.playlist,
    this.playlistTitle,
    this.initialPlaylistIndex = 0,
    this.startSeconds,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const _autoplayPreferenceKey = 'ct_video_autoplay_v1';
  static const _recommendationsPageSize = 20;
  final ApiClient _apiClient = ApiClient();
  final ChannelService _channelService = ChannelService();

  late String _activeVideoId;
  Video? _video;
  List<Video> _relatedVideos = [];
  final ScrollController _watchScrollController = ScrollController();
  bool _isLoadingRelated = false;
  bool _hasMoreRelated = true;
  int _relatedGeneration = 0;
  int _videoDetailsGeneration = 0;
  int? _autoplayCountdown;
  Timer? _autoplayCountdownTimer;
  DateTime? _relatedCursorPublishedBefore;
  String? _relatedCursorBeforeId;
  List<Video> _playlist = [];
  int _playlistIndex = 0;
  bool _isDescriptionExpanded = false;

  AudioTrack? _matchedAudioTrack;

  double _currentPositionSeconds = 0.0;
  double? _restoredStartSeconds;
  double? _activeStartSeconds;
  Timer? _positionSaveTimer;

  /// Persistent GlobalKey to ensure the underlying platform player (WebView / iframe)
  /// is never unmounted or reloaded across layout changes, rotation, or fullscreen toggles.
  final GlobalKey _playerSubtreeKey = GlobalKey(debugLabel: 'video_player_subtree');

  /// App-level fullscreen toggle.
  bool _isFullScreen = false;

  /// Set to true after the user explicitly taps the fullscreen-exit button.
  /// Prevents physical landscape rotation from immediately re-triggering
  /// fullscreen until the device returns to portrait orientation.
  bool _userExitedFullscreen = false;

  PlaylistLoopMode _loopMode = PlaylistLoopMode.off;
  bool _isShuffle = false;
  bool _isAutoplay = true;

  @override
  void initState() {
    super.initState();
    AudioPlayerController.instance.pause();
    _activeVideoId = widget.videoId;
    _video = widget.initialVideo;
    _activeStartSeconds = widget.startSeconds;
    _playlist = widget.playlist != null ? List.from(widget.playlist!) : [];
    _playlistIndex = widget.initialPlaylistIndex;
    _watchScrollController.addListener(_onWatchScroll);

    if (_video != null) {
      UserService().addToHistory(_video!);
    }

    if (widget.startSeconds == null) {
      UserService().getVideoPosition(_activeVideoId).then((saved) {
        if (mounted && saved > 5) {
          setState(() {
            _restoredStartSeconds = saved;
          });
        }
      });
    }

    _channelService.loadSubscriptions();
    _channelService.fetchChannels();
    _loadAutoplayPreference();
    if (_video != null) _loadRelatedVideos(reset: true);
    _loadVideoDetails();
    _checkAudioTrack();
  }

  Future<void> _loadAutoplayPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _isAutoplay = prefs.getBool(_autoplayPreferenceKey) ?? true);
      }
    } catch (_) {}
  }

  Future<void> _setAutoplay(bool enabled) async {
    setState(() => _isAutoplay = enabled);
    if (!enabled) _cancelAutoplayCountdown();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoplayPreferenceKey, enabled);
    } catch (_) {}
  }

  Future<void> _checkAudioTrack() async {
    try {
      final track = await AudioCatalogService().findTrackByYoutubeId(_activeVideoId);
      if (mounted) {
        setState(() {
          _matchedAudioTrack = track;
        });
      }
    } catch (_) {}
  }

  void _playNextInPlaylist() {
    if (_playlist.isEmpty) return;
    if (_playlistIndex < _playlist.length - 1) {
      _selectVideoFromPlaylist(_playlistIndex + 1);
    } else if (_loopMode == PlaylistLoopMode.all) {
      _selectVideoFromPlaylist(0);
    }
  }

  void _playNextNow() {
    _cancelAutoplayCountdown();
    final isCurrentPlaylistVideo = _playlistIndex >= 0 &&
        _playlistIndex < _playlist.length &&
        _playlist[_playlistIndex].id == _activeVideoId;
    if (isCurrentPlaylistVideo && _playlistIndex < _playlist.length - 1) {
      _playNextInPlaylist();
      return;
    }
    if (isCurrentPlaylistVideo && _loopMode == PlaylistLoopMode.all) {
      _selectVideoFromPlaylist(0);
      return;
    }
    if (_relatedVideos.isNotEmpty) {
      _navigateToVideo(_relatedVideos.first);
    } else if (_hasMoreRelated) {
      _loadMoreRelatedVideos(_relatedGeneration).then((_) {
        if (mounted && _relatedVideos.isNotEmpty) {
          _navigateToVideo(_relatedVideos.first);
        }
      });
    }
  }

  void _playPreviousInPlaylist() {
    if (_playlist.isNotEmpty && _playlistIndex > 0) {
      _selectVideoFromPlaylist(_playlistIndex - 1);
    }
  }

  void _selectVideoFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    _cancelAutoplayCountdown();
    _saveAndResetPosition();
    final nextVid = _playlist[index];
    setState(() {
      _playlistIndex = index;
      _activeVideoId = nextVid.id;
      _video = nextVid;
      _activeStartSeconds = null;
      _restoredStartSeconds = null;
    });
    _loadRelatedVideos(reset: true);
    UserService().addToHistory(nextVid);
    _loadVideoDetails();
    _checkAudioTrack();
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffle = !_isShuffle;
      if (_isShuffle && _playlist.isNotEmpty) {
        final current = _playlist[_playlistIndex];
        final remaining = List<Video>.from(_playlist)..removeAt(_playlistIndex);
        remaining.shuffle();
        _playlist = [current, ...remaining];
        _playlistIndex = 0;
      }
    });
  }

  Future<void> _loadVideoDetails() async {
    final generation = ++_videoDetailsGeneration;
    final requestedVideoId = _activeVideoId;
    final shouldLoadRecommendations = _video == null;
    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get('/api/videos/$requestedVideoId');
      } catch (_) {
        response = await _apiClient.dio.get('/videos/$requestedVideoId');
      }

      if (response.statusCode == 200 && response.data != null) {
        final loaded = Video.fromJson(response.data as Map<String, dynamic>);
        if (mounted && generation == _videoDetailsGeneration) {
          setState(() {
            _video = loaded;
          });
        }
        if (generation != _videoDetailsGeneration) return;
        UserService().addToHistory(loaded);
        if (shouldLoadRecommendations) {
          await _loadRelatedVideos(reset: true);
        }
      }
    } catch (e) {
      debugPrint('Error loading video details: $e');
      if (generation == _videoDetailsGeneration &&
          shouldLoadRecommendations &&
          _video != null) {
        await _loadRelatedVideos(reset: true);
      }
    }
  }

  Future<void> _loadRelatedVideos({bool reset = false}) async {
    final current = _video;
    if (current == null || current.channelId.isEmpty) return;
    if (reset) {
      _relatedGeneration++;
      _isLoadingRelated = false;
      _relatedVideos = [];
      _hasMoreRelated = true;
      _relatedCursorPublishedBefore = current.publishedAt;
      _relatedCursorBeforeId = current.id;
      if (_watchScrollController.hasClients) {
        _watchScrollController.jumpTo(0);
      }
    }
    await _loadMoreRelatedVideos(_relatedGeneration);
  }

  Future<void> _loadMoreRelatedVideos(int generation) async {
    final current = _video;
    if (_isLoadingRelated || !_hasMoreRelated || current == null) return;
    _isLoadingRelated = true;
    if (mounted) setState(() {});
    try {
      final queryParams = <String, dynamic>{
        'type': 'VIDEO',
        'sort': 'latest',
        'channelId': current.channelId,
        'limit': _recommendationsPageSize,
        if (_relatedCursorPublishedBefore != null)
          'publishedBefore': _relatedCursorPublishedBefore!.toIso8601String(),
        if (_relatedCursorBeforeId != null) 'beforeId': _relatedCursorBeforeId,
      };

      dynamic response;
      try {
        response = await _apiClient.dio
            .get('/api/videos', queryParameters: queryParams);
      } catch (_) {
        response =
            await _apiClient.dio.get('/videos', queryParameters: queryParams);
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        if (mounted && generation == _relatedGeneration) {
          final page = list
              .whereType<Map<String, dynamic>>()
              .where((json) => !Short.isShort(json))
              .map((json) => Video.fromJson(json))
              .where((video) => video.id != current.id && video.type != 'SHORT')
              .toList();
          final knownIds = _relatedVideos.map((video) => video.id).toSet();
          final uniquePage = page.where((video) => knownIds.add(video.id)).toList();
          setState(() {
            _relatedVideos = [..._relatedVideos, ...uniquePage];
            _hasMoreRelated = list.length == _recommendationsPageSize;
            if (page.isNotEmpty) {
              final last = page.last;
              _relatedCursorPublishedBefore = last.publishedAt;
              _relatedCursorBeforeId = last.id;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading related videos: $e');
    } finally {
      if (generation == _relatedGeneration) {
        _isLoadingRelated = false;
        if (mounted) setState(() {});
      }
    }
  }

  void _onWatchScroll() {
    if (!_watchScrollController.hasClients || _isLoadingRelated || !_hasMoreRelated) return;
    if (_watchScrollController.position.extentAfter < 500) {
      _loadMoreRelatedVideos(_relatedGeneration);
    }
  }

  Future<void> _onPlaybackEnded() async {
    if (!mounted || !_isAutoplay) return;
    final isCurrentPlaylistVideo = _playlistIndex >= 0 &&
        _playlistIndex < _playlist.length &&
        _playlist[_playlistIndex].id == _activeVideoId;
    if (isCurrentPlaylistVideo && _playlistIndex < _playlist.length - 1) {
      _startAutoplayCountdown(_playNextInPlaylist);
      return;
    }
    if (isCurrentPlaylistVideo && _loopMode == PlaylistLoopMode.all) {
      _startAutoplayCountdown(() => _selectVideoFromPlaylist(0));
      return;
    }
    if (_relatedVideos.isEmpty && _hasMoreRelated) {
      await _loadMoreRelatedVideos(_relatedGeneration);
    }
    if (_relatedVideos.isNotEmpty) {
      _startAutoplayCountdown(() => _navigateToVideo(_relatedVideos.first));
    }
  }

  void _startAutoplayCountdown(VoidCallback playNext) {
    _cancelAutoplayCountdown();
    setState(() => _autoplayCountdown = 5);
    _autoplayCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isAutoplay) {
        timer.cancel();
        return;
      }
      final remaining = _autoplayCountdown ?? 0;
      if (remaining <= 1) {
        timer.cancel();
        setState(() => _autoplayCountdown = null);
        playNext();
      } else {
        setState(() => _autoplayCountdown = remaining - 1);
      }
    });
  }

  void _cancelAutoplayCountdown() {
    _autoplayCountdownTimer?.cancel();
    _autoplayCountdownTimer = null;
    if (_autoplayCountdown != null && mounted) {
      setState(() => _autoplayCountdown = null);
    }
  }

  void _saveAndResetPosition() {
    _positionSaveTimer?.cancel();
    if (_currentPositionSeconds > 0) {
      UserService().saveVideoPosition(_activeVideoId, _currentPositionSeconds);
    }
    _currentPositionSeconds = 0;
  }

  void _shareVideo() {
    final title = _video?.title;
    final url = DeepLinkService.video(_activeVideoId);
    final text = (title != null && title.trim().isNotEmpty)
        ? 'Watch "$title" on ${AppConfig.appName}:\n$url'
        : 'Watch on ${AppConfig.appName}:\n$url';
    Share.share(text, subject: title ?? 'Watch on ${AppConfig.appName}');
  }

  Future<void> _openInYouTubeApp() async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=$_activeVideoId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openShortsTrimmer() {
    final durationSec = _video != null
        ? Short.parseDurationInSeconds(_video!.duration).toDouble()
        : 1800.0;

    final initialPlayhead =
        _currentPositionSeconds > 0 ? _currentPositionSeconds : 60.0;

    showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShortsTrimmerSheet(
        sourceVideoId: _activeVideoId,
        sourceVideoTitle: _video?.title ?? 'Sermon Clip',
        sourceVideoThumbnail: _video?.thumbnailUrl,
        currentPlayheadSeconds: initialPlayhead,
        totalDurationSeconds: durationSec > 0 ? durationSec : 1800.0,
      ),
    );
  }

  void _navigateToVideo(Video video) {
    _cancelAutoplayCountdown();
    _saveAndResetPosition();
    final playlistIndex = _playlist.indexWhere((item) => item.id == video.id);
    setState(() {
      if (playlistIndex >= 0) {
        _playlistIndex = playlistIndex;
      } else {
        _playlist = [];
        _playlistIndex = 0;
      }
      _activeVideoId = video.id;
      _video = video;
      _activeStartSeconds = null;
      _restoredStartSeconds = null;
    });
    _loadRelatedVideos(reset: true);
    _loadVideoDetails();
  }


  @override
  void dispose() {
    _positionSaveTimer?.cancel();
    _autoplayCountdownTimer?.cancel();
    _watchScrollController
      ..removeListener(_onWatchScroll)
      ..dispose();
    if (_currentPositionSeconds > 0) {
      UserService().saveVideoPosition(_activeVideoId, _currentPositionSeconds);
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final screenClass = ScreenClass.of(context);
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < 600;
    // On native mobile phones, rotating to landscape automatically enters fullscreen.
    // On tablets, web, and desktop, landscape is normal orientation and renders
    // the two-column YouTube layout.
    final isPhoneLandscape = isPhone && orientation == Orientation.landscape;
    // When the device returns to portrait, clear the "user exited" gate so that
    // the next landscape rotation can auto-enter fullscreen again.
    if (!isPhoneLandscape && _userExitedFullscreen) {
      // Schedule outside build to avoid setState-during-build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _userExitedFullscreen = false);
      });
    }
    // Auto-enter fullscreen on phone landscape ONLY when the user hasn't
    // explicitly exited fullscreen during the current landscape session.
    final isFullscreen = _isFullScreen ||
        (!kIsWeb && isPhoneLandscape && !_userExitedFullscreen);

    return buildPlatformVideoPlayer(
      videoId: _activeVideoId,
      startSeconds: _activeStartSeconds ?? _restoredStartSeconds,
      isFullScreen: isFullscreen,
      onToggleFullScreen: () {
        if (_isFullScreen || isPhoneLandscape) {
          // Exiting fullscreen: lock portrait so the sensor-based auto-fullscreen
          // doesn't immediately re-trigger while the device is still landscape.
          setState(() {
            _isFullScreen = false;
            _userExitedFullscreen = true;
          });
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              SystemChrome.setPreferredOrientations(DeviceOrientation.values);
            }
          });
        } else {
          setState(() => _isFullScreen = true);
        }
      },
      onPositionChanged: (pos) {
        _currentPositionSeconds = pos.inMilliseconds / 1000.0;
        _positionSaveTimer?.cancel();
        _positionSaveTimer = Timer(const Duration(seconds: 4), () {
          if (_currentPositionSeconds > 0) {
            UserService()
                .saveVideoPosition(_activeVideoId, _currentPositionSeconds);
          }
        });
      },
      onEnded: _onPlaybackEnded,
      builder: (context, player) {
        final tokens = context.tokens;
        // KeyedSubtree guarantees that Flutter will NEVER tear down the native
        // WebView / HtmlElementView when switching between fullscreen and normal trees.
        final persistentPlayer = KeyedSubtree(
          key: _playerSubtreeKey,
          child: player,
        );
        final playerSurface = _buildPlayerSurface(context, persistentPlayer);

        if (isFullscreen) {
          return PopScope(
            canPop: !_isFullScreen,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _isFullScreen) {
                // Exiting fullscreen via back button: also lock portrait.
                setState(() {
                  _isFullScreen = false;
                  _userExitedFullscreen = true;
                });
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.portraitDown,
                ]);
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    SystemChrome.setPreferredOrientations(
                        DeviceOrientation.values);
                  }
                });
              }
            },
            child: Scaffold(
              backgroundColor: tokens.scrim,
              body: SizedBox.expand(child: playerSurface),
            ),
          );
        }

        return Scaffold(
          appBar: _buildAppBar(context),
          body: SafeArea(
            top: false,
            bottom: true,
            child: SingleChildScrollView(
              controller: _watchScrollController,
              child: screenClass.isCompact
                  ? _buildCompactLayout(context, playerSurface)
                  : _buildExpandedLayout(context, playerSurface),
            ),
          ),
        );
      },
    );
  }

  // ── Top Navigation Bar ─────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final tokens = context.tokens;
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: tokens.background,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_fill, color: context.primary, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              AppConfig.appName.isNotEmpty
                  ? AppConfig.appName
                  : 'ChristianApp',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      actions: needsCollapsedActions(MediaQuery.sizeOf(context).width)
          ? [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More',
                onSelected: (value) {
                  switch (value) {
                    case 'share':
                      _shareVideo();
                      break;
                    case 'youtube':
                      _openInYouTubeApp();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (_video != null)
                    const PopupMenuItem(
                      value: 'share',
                      child: ListTile(
                        leading: Icon(Icons.share_outlined),
                        title: Text('Share'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'youtube',
                    child: ListTile(
                      leading: Icon(Icons.open_in_new_rounded),
                      title: Text('Watch on YouTube'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ]
          : [
              if (_video != null)
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Share',
                  onPressed: _shareVideo,
                ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded),
                tooltip: 'Watch on YouTube',
                onPressed: _openInYouTubeApp,
              ),
            ],
    );
  }

  // ── Compact (Phone Portrait) Layout ────────────────────────────────────────
  Widget _buildCompactLayout(BuildContext context, Widget player) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: tokens.scrim,
            child: player,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildTitle(context, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildViewsAndDate(context),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildChannelInfo(context),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildActionButtons(context),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildDescriptionCard(context),
        ),
        const SizedBox(height: 14),
        if (_playlist.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: _buildPlaylistWidget(context),
          ),
        _buildRelatedHeader(context),
        ..._relatedCards(context),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Real YouTube Desktop / Tablet (Medium & Expanded) Layout ───────────────
  Widget _buildExpandedLayout(BuildContext context, Widget player) {
    final tokens = context.tokens;
    final screenClass = ScreenClass.of(context);
    final isExpanded = screenClass == ScreenClass.expanded;
    final sidebarWidth = isExpanded ? 380.0 : 240.0;
    final outerPadding = isExpanded ? 24.0 : 16.0;

    return Center(
      child: MaxWidthBox(
        maxWidth: 1680,
        padding: EdgeInsets.symmetric(horizontal: outerPadding, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            color: tokens.scrim,
                            child: player,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildTitle(context, fontSize: 20),
                  const SizedBox(height: 8),
                  _buildViewsAndDate(context),
                  const SizedBox(height: 8),
                  _buildDesktopChannelAndActionsRow(context),
                  const SizedBox(height: 16),
                  _buildDescriptionCard(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            SizedBox(width: outerPadding),
            SizedBox(
              width: sidebarWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_playlist.isNotEmpty) ...[
                    _buildPlaylistWidget(context),
                    const SizedBox(height: 16),
                  ],
                  _buildRelatedHeader(context),
                  ..._relatedCards(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Desktop Channel & Actions Row ──────────────────────────────────────────
  Widget _buildDesktopChannelAndActionsRow(BuildContext context) {
    final channelWidget = _buildChannelInfo(context);
    final actionsWidget = _buildActionButtons(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: channelWidget),
              const SizedBox(width: 16),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: actionsWidget,
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            channelWidget,
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: actionsWidget,
            ),
          ],
        );
      },
    );
  }

  // ── Video Title ────────────────────────────────────────────────────────────
  Widget _buildTitle(BuildContext context, {required double fontSize}) {
    return Text(
      _video?.title ?? 'Loading video...',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        height: 1.28,
        color: context.tokens.onSurface,
      ),
    );
  }

  // ── Views & Upload Date ────────────────────────────────────────────────────
  Widget _buildViewsAndDate(BuildContext context) {
    final tokens = context.tokens;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${Formatters.formatViews(_video?.viewCount ?? 0)} views',
          style: TextStyle(
            color: tokens.onSurfaceMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_video?.publishedAt != null)
          Text(
            '•  ${Formatters.formatTimeAgo(_video!.publishedAt)}',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  // ── Channel Info Header ────────────────────────────────────────────────────
  Widget _buildChannelInfo(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: _channelService,
      builder: (context, _) {
        final isSubscribed = _video?.channelId.isNotEmpty == true &&
            _channelService.subscribedChannelIds.contains(_video!.channelId);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  if (_video?.channelId.isNotEmpty == true) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChannelDetailScreen(channelId: _video!.channelId),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    ChannelAvatar(
                      avatarUrl: _video?.channelAvatarUrl,
                      channelTitle: _video?.channelTitle ?? 'Channel',
                      radius: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _video?.channelTitle ?? 'Channel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (_video?.subscriberCount != null)
                            Text(
                              '${Formatters.formatSubscribers(_video!.subscriberCount)} subscribers',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Follow Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isSubscribed ? tokens.surfaceVariant : context.accent,
                foregroundColor:
                    isSubscribed ? tokens.onSurface : tokens.onScrim,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: () {
                if (_video?.channelId.isNotEmpty == true) {
                  _channelService.toggleFollow(_video!.channelId);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSubscribed ? Icons.check : Icons.add,
                    size: 15,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSubscribed ? 'Following' : 'Follow',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Action Buttons (Like, Clip, Share, Save, YouTube) ──────────────────────
  Widget _buildActionButtons(BuildContext context) {
    return AnimatedBuilder(
      animation: UserSyncService.instance,
      builder: (context, _) {
        final targetId = _video?.id ?? _activeVideoId;
        final isLiked = targetId.isNotEmpty &&
            UserSyncService.instance.isLiked(
              UserSyncService.likedVideoType,
              targetId,
            );
        return VideoActionBar(
          isLiked: isLiked,
          onToggleLike: () {
            if (targetId.isEmpty) return;
            UserSyncService.instance.setLiked(
              itemType: UserSyncService.likedVideoType,
              itemId: targetId,
              liked: !isLiked,
            );
          },
          matchedAudioTrack: _matchedAudioTrack,
          onListenAudio: _matchedAudioTrack == null
              ? null
              : () {
                  final pos = _currentPositionSeconds.toInt();
                  pausePlatformMainVideo();
                  AudioPlayerController.instance.playTrack(
                    _matchedAudioTrack!,
                    resumePositionSec: pos,
                  );
                  FullAudioPlayerSheet.show(context);
                },
          onClip: _openShortsTrimmer,
          onShare: _shareVideo,
          onSave: () {
            if (_video != null) {
              VideoOptionsBottomSheet.show(
                context,
                video: _video!,
              );
            }
          },
          onOpenYouTube: _openInYouTubeApp,
        );
      },
    );
  }

  // ── Description Box ────────────────────────────────────────────────────────
  Widget _buildDescriptionCard(BuildContext context) {
    final tokens = context.tokens;
    final description = _video?.description;
    final hasDescription = description != null && description.isNotEmpty;

    return InkWell(
      onTap: hasDescription
          ? () =>
              setState(() => _isDescriptionExpanded = !_isDescriptionExpanded)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${Formatters.formatViews(_video?.viewCount ?? 0)} views',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (_video?.publishedAt != null)
                  Text(
                    '•  ${Formatters.formatTimeAgo(_video!.publishedAt)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                if (_video?.category != null && _video!.category!.isNotEmpty)
                  Text(
                    '•  ${_video!.category}',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            if (hasDescription) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: _isDescriptionExpanded ? null : 3,
                overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: tokens.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isDescriptionExpanded ? 'Show less' : '...more',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Playlist Widget ────────────────────────────────────────────────────────
  Widget _buildPlaylistWidget(BuildContext context) {
    return YouTubePlaylistWidget(
      title: widget.playlistTitle ?? 'Playlist',
      playlist: _playlist,
      currentIndex: _playlistIndex,
      onSelectVideo: _selectVideoFromPlaylist,
      onPrevious: _playPreviousInPlaylist,
      onNext: _playNextInPlaylist,
      loopMode: _loopMode,
      onToggleLoop: (mode) => setState(() => _loopMode = mode),
      isShuffle: _isShuffle,
      onToggleShuffle: _toggleShuffle,
      isAutoplay: _isAutoplay,
      onToggleAutoplay: _setAutoplay,
    );
  }

  Widget _buildRelatedHeader(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Up Next',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: tokens.onSurface,
              ),
            ),
          ),
          if (_playlist.isEmpty) ...[
            const Text('Autoplay', style: TextStyle(fontSize: 12)),
            Switch(
              value: _isAutoplay,
              onChanged: _setAutoplay,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _relatedCards(BuildContext context) {
    if (_relatedVideos.isEmpty && _isLoadingRelated) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_relatedVideos.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('No more videos from this channel.')),
        ),
      ];
    }
    return [
      ..._relatedVideos.map((video) => RecommendationVideoCard(
            video: video,
            onTap: () => _navigateToVideo(video),
          )),
      if (_isLoadingRelated)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (!_hasMoreRelated)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'You’re all caught up',
              style: TextStyle(color: context.tokens.onSurfaceMuted),
            ),
          ),
        ),
    ];
  }

  Widget _buildPlayerSurface(BuildContext context, Widget player) {
    final tokens = context.tokens;
    if (_autoplayCountdown == null) return player;
    final nextVideo = _playlist.isNotEmpty && _playlistIndex < _playlist.length - 1
        ? _playlist[_playlistIndex + 1]
        : (_relatedVideos.isNotEmpty ? _relatedVideos.first : null);
    return Stack(
      fit: StackFit.expand,
      children: [
        player,
        ColoredBox(
          color: tokens.scrim.withValues(alpha: 0.82),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Up next in $_autoplayCountdown seconds',
                    style: TextStyle(color: tokens.onScrimMuted),
                    textAlign: TextAlign.center,
                  ),
                  if (nextVideo != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      nextVideo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.onScrim,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _cancelAutoplayCountdown,
                        child: Text('Cancel', style: TextStyle(color: tokens.onScrim)),
                      ),
                      FilledButton(
                        onPressed: _playNextNow,
                        child: const Text('Play now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
