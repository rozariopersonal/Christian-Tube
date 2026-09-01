import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/recommendation_video_card.dart';
import '../../shared/ui/video_options_bottom_sheet.dart';
import '../channels/channel_service.dart';
import '../profile/user_service.dart';
import '../../core/config/app_config.dart';
import 'widgets/youtube_playlist_widget.dart';
import 'players/universal_video_player.dart';
import 'widgets/shorts_trimmer_sheet.dart';
import '../../core/models/short.dart';

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
  final ApiClient _apiClient = ApiClient();
  final ChannelService _channelService = ChannelService();

  late String _activeVideoId;
  Video? _video;
  List<Video> _relatedVideos = [];
  List<Video> _playlist = [];
  int _playlistIndex = 0;
  bool _isDescriptionExpanded = false;
  bool _isLiked = false;
  bool _isDisliked = false;

  double _currentPositionSeconds = 0.0;

  /// App-level fullscreen toggle.
  bool _isFullScreen = false;

  PlaylistLoopMode _loopMode = PlaylistLoopMode.off;
  bool _isShuffle = false;
  bool _isAutoplay = true;

  @override
  void initState() {
    super.initState();
    _activeVideoId = widget.videoId;
    _video = widget.initialVideo;
    _playlist = widget.playlist != null ? List.from(widget.playlist!) : [];
    _playlistIndex = widget.initialPlaylistIndex;

    if (_video != null) {
      UserService().addToHistory(_video!);
    }

    _channelService.loadSubscriptions();
    _channelService.fetchChannels();
    _loadVideoDetails();
    _loadRelatedVideos();
  }

  void _playNextInPlaylist() {
    if (_playlist.isEmpty) return;
    if (_playlistIndex < _playlist.length - 1) {
      _selectVideoFromPlaylist(_playlistIndex + 1);
    } else if (_loopMode == PlaylistLoopMode.all) {
      _selectVideoFromPlaylist(0);
    }
  }

  void _playPreviousInPlaylist() {
    if (_playlist.isNotEmpty && _playlistIndex > 0) {
      _selectVideoFromPlaylist(_playlistIndex - 1);
    }
  }

  void _selectVideoFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final nextVid = _playlist[index];
    setState(() {
      _playlistIndex = index;
      _activeVideoId = nextVid.id;
      _video = nextVid;
    });
    UserService().addToHistory(nextVid);
    _loadVideoDetails();
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
    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get('/api/videos/$_activeVideoId');
      } catch (_) {
        response = await _apiClient.dio.get('/videos/$_activeVideoId');
      }

      if (response.statusCode == 200 && response.data != null) {
        final loaded = Video.fromJson(response.data as Map<String, dynamic>);
        if (mounted) {
          setState(() {
            _video = loaded;
          });
        }
        UserService().addToHistory(loaded);
      }
    } catch (e) {
      debugPrint('Error loading video details: $e');
    }
  }

  Future<void> _loadRelatedVideos() async {
    try {
      final queryParams = <String, dynamic>{
        'type': 'VIDEO',
        'limit': 20,
      };
      if (_video?.category != null &&
          _video!.category != 'All' &&
          _video!.category!.isNotEmpty) {
        queryParams['category'] = _video!.category;
      }

      dynamic response;
      try {
        response =
            await _apiClient.dio.get('/api/videos', queryParameters: queryParams);
      } catch (_) {
        response =
            await _apiClient.dio.get('/videos', queryParameters: queryParams);
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        if (mounted) {
          setState(() {
            _relatedVideos = list
                .whereType<Map<String, dynamic>>()
                .where((json) => !Short.isShort(json))
                .map((v) => Video.fromJson(v))
                .where((v) => v.id != _activeVideoId && v.type != 'SHORT')
                .take(15)
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading related videos: $e');
    }
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
    setState(() {
      _activeVideoId = video.id;
      _video = video;
    });
    _loadVideoDetails();
    _loadRelatedVideos();
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/feed');
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final screenClass = ScreenClass.of(context);
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < 600;
    // On native mobile phones, rotating to landscape automatically enters fullscreen.
    // On tablets, web, and desktop, landscape is normal orientation and renders
    // the two-column YouTube layout.
    final isPhoneLandscape = isPhone && orientation == Orientation.landscape;
    final isFullscreen = _isFullScreen || (!kIsWeb && isPhoneLandscape);

    return buildPlatformVideoPlayer(
      videoId: _activeVideoId,
      startSeconds: widget.startSeconds,
      isFullScreen: isFullscreen,
      onToggleFullScreen: () => setState(() => _isFullScreen = !_isFullScreen),
      onPositionChanged: (pos) {
        _currentPositionSeconds = pos.inMilliseconds / 1000.0;
      },
      builder: (context, player) {
        if (isFullscreen) {
          return PopScope(
            canPop: !_isFullScreen,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _isFullScreen) {
                setState(() => _isFullScreen = false);
              }
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SizedBox.expand(child: player),
            ),
          );
        }

        return PopScope(
          canPop: true,
          child: Scaffold(
            appBar: _buildAppBar(context),
            body: SafeArea(
              top: false,
              bottom: true,
              child: SingleChildScrollView(
                child: screenClass.isCompact
                    ? _buildCompactLayout(context, player)
                    : _buildExpandedLayout(context, player),
              ),
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
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back',
        onPressed: () => _handleBack(context),
      ),
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_fill, color: context.primary, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              AppConfig.appName.isNotEmpty ? AppConfig.appName : 'ChristianTube',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      actions: [
        if (_video != null)
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () {
              Share.share('${AppConfig.apiBaseUrl}/watch/$_activeVideoId');
            },
          ),
        IconButton(
          icon: const Icon(Icons.open_in_new_rounded),
          tooltip: 'Watch on YouTube',
          onPressed: _openInYouTubeApp,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Compact (Phone Portrait) Layout ────────────────────────────────────────
  Widget _buildCompactLayout(BuildContext context, Widget player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Video Player (fills width)
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: player,
          ),
        ),
        const SizedBox(height: 12),

        // Title & Views
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

        // Channel Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildChannelInfo(context),
        ),
        const SizedBox(height: 12),

        // Horizontally Scrollable Action Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildActionButtons(context),
        ),
        const SizedBox(height: 12),

        // Expandable Description Box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildDescriptionCard(context),
        ),
        const SizedBox(height: 14),

        // Playlist Queue Widget (if active)
        if (_playlist.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: _buildPlaylistWidget(context),
          ),

        // Up Next Recommendations
        ..._relatedChildren(context),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Real YouTube Desktop / Tablet (Medium & Expanded) Layout ───────────────
  Widget _buildExpandedLayout(BuildContext context, Widget player) {
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
            // ── Primary Column (Left) ────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Video Player (16:9 Aspect Ratio with rounded corners, capped at 1280)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            color: Colors.black,
                            child: player,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Video Title (Large bold typography)
                  _buildTitle(context, fontSize: 20),
                  const SizedBox(height: 8),

                  // Channel & Action Bar (Desktop Row or responsive wrap)
                  _buildDesktopChannelAndActionsRow(context),
                  const SizedBox(height: 16),

                  // Expandable Description Box
                  _buildDescriptionCard(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            SizedBox(width: outerPadding),

            // ── Secondary Column (Right Sidebar) ─────────────────────────────
            SizedBox(
              width: sidebarWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_playlist.isNotEmpty) ...[
                    _buildPlaylistWidget(context),
                    const SizedBox(height: 16),
                  ],
                  ..._relatedChildren(context),
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
              actionsWidget,
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (_video?.subscriberCount != null)
                    Text(
                      '${Formatters.formatSubscribers(_video!.subscriberCount)} subscribers',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Subscribe Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSubscribed
                    ? tokens.surfaceVariant
                    : tokens.onSurface,
                foregroundColor: isSubscribed
                    ? tokens.onSurfaceMuted
                    : tokens.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                if (_video?.channelId.isNotEmpty == true) {
                  _channelService.toggleSubscribe(_video!.channelId);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSubscribed ? Icons.notifications_active : Icons.add,
                    size: 15,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSubscribed ? 'Subscribed' : 'Subscribe',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Action Buttons (Like, Dislike, Clip, Share, Save, YouTube) ─────────────
  Widget _buildActionButtons(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like / Dislike Segmented Pill
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                onTap: () {
                  setState(() {
                    _isLiked = !_isLiked;
                    if (_isLiked) _isDisliked = false;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        _isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 16,
                        color: _isLiked ? Theme.of(context).colorScheme.primary : null,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isLiked ? '1' : 'Like',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 18,
                color: tokens.surfaceBorder,
              ),
              InkWell(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                onTap: () {
                  setState(() {
                    _isDisliked = !_isDisliked;
                    if (_isDisliked) _isLiked = false;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Icon(
                    _isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                    size: 16,
                    color: _isDisliked ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Clip Short
        _buildActionPill(
          icon: Icons.content_cut,
          label: 'Clip',
          onTap: _openShortsTrimmer,
        ),
        const SizedBox(width: 8),

        // Share
        _buildActionPill(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () {
            Share.share('${AppConfig.apiBaseUrl}/watch/$_activeVideoId');
          },
        ),
        const SizedBox(width: 8),

        // Save
        _buildActionPill(
          icon: Icons.bookmark_add_outlined,
          label: 'Save',
          onTap: () {
            if (_video != null) {
              showAdaptiveBottomSheet(
                context: context,
                builder: (ctx) => VideoOptionsBottomSheet(video: _video!),
              );
            }
          },
        ),
        const SizedBox(width: 8),

        // YouTube
        _buildActionPill(
          icon: Icons.open_in_new,
          label: 'YouTube',
          onTap: _openInYouTubeApp,
        ),
      ],
    );
  }

  // ── Description Box ────────────────────────────────────────────────────────
  Widget _buildDescriptionCard(BuildContext context) {
    final tokens = context.tokens;
    final description = _video?.description;
    final hasDescription = description != null && description.isNotEmpty;

    return InkWell(
      onTap: hasDescription
          ? () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded)
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (_video?.publishedAt != null)
                  Text(
                    '•  ${Formatters.formatTimeAgo(_video!.publishedAt)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
      onToggleAutoplay: (val) => setState(() => _isAutoplay = val),
    );
  }

  // ── Up Next / Related Videos List ──────────────────────────────────────────
  List<Widget> _relatedChildren(BuildContext context) {
    final tokens = context.tokens;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          'Up Next',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: tokens.onSurface,
          ),
        ),
      ),
      const SizedBox(height: 4),

      if (_relatedVideos.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('Loading recommendations...')),
        )
      else
        ..._relatedVideos.map((rv) => RecommendationVideoCard(
              video: rv,
              onTap: () => _navigateToVideo(rv),
            )),
    ];
  }

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.tokens.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}