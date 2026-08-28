import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
      dynamic response;
      try {
        response = await _apiClient.dio.get('/api/videos');
      } catch (_) {
        response = await _apiClient.dio.get('/videos');
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        if (mounted) {
          setState(() {
            _relatedVideos = list
                .whereType<Map<String, dynamic>>()
                .map((v) => Video.fromJson(v))
                .where((v) => v.id != _activeVideoId)
                .take(12)
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

    final initialPlayhead = _currentPositionSeconds > 0
        ? _currentPositionSeconds
        : 60.0;

    showModalBottomSheet(
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasPlaylist = _playlist.isNotEmpty;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    return buildPlatformVideoPlayer(
      videoId: _activeVideoId,
      startSeconds: widget.startSeconds,
      onPositionChanged: (pos) {
        _currentPositionSeconds = pos.inMilliseconds / 1000.0;
      },
      builder: (context, player) {
        if (isLandscape) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(child: player),
          );
        }

        return Scaffold(
          body: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                // YouTube Player
                player,

                // Video Metadata & Recommendations
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    children: [
                      // Video Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          _video?.title ?? 'Loading video...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),

                    // View Count & Upload Date
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Text(
                            '${Formatters.formatViews(_video?.viewCount ?? 0)} views',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_video?.publishedAt != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '•  ${Formatters.formatTimeAgo(_video!.publishedAt)}',
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Channel Header Row
                    AnimatedBuilder(
                      animation: _channelService,
                      builder: (context, _) {
                        final isSubscribed = _video?.channelId.isNotEmpty == true &&
                            _channelService.subscribedChannelIds.contains(_video!.channelId);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
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
                                  children: [
                                    Text(
                                      _video?.channelTitle ?? 'Channel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    if (_video?.subscriberCount != null)
                                      Text(
                                        '${Formatters.formatSubscribers(_video!.subscriberCount)} subscribers',
                                        style: TextStyle(
                                          color: isDark ? Colors.white60 : Colors.black54,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Subscribe Button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSubscribed
                                      ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                                      : (isDark ? Colors.white : Colors.black),
                                  foregroundColor: isSubscribed
                                      ? (isDark ? Colors.white70 : Colors.black87)
                                      : (isDark ? Colors.black : Colors.white),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                onPressed: () {
                                  if (_video?.channelId.isNotEmpty == true) {
                                    _channelService.toggleSubscribe(_video!.channelId);
                                  }
                                },
                                icon: isSubscribed
                                    ? const Icon(Icons.notifications_active, size: 16)
                                    : const Icon(Icons.add, size: 16),
                                label: Text(
                                  isSubscribed ? 'Subscribed' : 'Subscribe',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Action Buttons Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          // Like / Dislike Pill
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
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
                                          color: _isLiked ? Colors.blue : null,
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
                                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
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
                                      color: _isDisliked ? Colors.red : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Clip Short (Up to 3 mins)
                          _buildActionPill(
                            icon: Icons.content_cut,
                            label: 'Clip',
                            onTap: _openShortsTrimmer,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),

                          // Share
                          _buildActionPill(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            onTap: () {
                              Share.share('${AppConfig.apiBaseUrl}/watch/$_activeVideoId');
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),

                          // Save
                          _buildActionPill(
                            icon: Icons.bookmark_add_outlined,
                            label: 'Save',
                            onTap: () {
                              if (_video != null) {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (ctx) => VideoOptionsBottomSheet(video: _video!),
                                );
                              }
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),

                          // Open in YouTube
                          _buildActionPill(
                            icon: Icons.open_in_new,
                            label: 'YouTube',
                            onTap: _openInYouTubeApp,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Expandable Description
                    if (_video?.description != null && _video!.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: InkWell(
                          onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${Formatters.formatViews(_video?.viewCount ?? 0)} views  ${_video?.publishedAt != null ? Formatters.formatTimeAgo(_video!.publishedAt) : ""}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _video!.description!,
                                  maxLines: _isDescriptionExpanded ? null : 3,
                                  overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isDescriptionExpanded ? 'Show less' : '...more',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),

                    // Playlist Widget
                    if (hasPlaylist)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: YouTubePlaylistWidget(
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
                        ),
                      ),

                    // Related Videos
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Text(
                        'Up Next',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
