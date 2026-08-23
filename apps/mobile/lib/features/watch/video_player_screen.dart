import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/recommendation_video_card.dart';
import '../../shared/ui/video_options_bottom_sheet.dart';
import '../channels/channel_service.dart';
import '../../core/config/app_config.dart';
import 'widgets/youtube_playlist_widget.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final Video? initialVideo;
  final List<Video>? playlist;
  final String? playlistTitle;
  final int initialPlaylistIndex;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    this.initialVideo,
    this.playlist,
    this.playlistTitle,
    this.initialPlaylistIndex = 0,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  final ApiClient _apiClient = ApiClient();
  final ChannelService _channelService = ChannelService();

  late String _activeVideoId;
  Video? _video;
  List<Video> _relatedVideos = [];
  List<Video> _playlist = [];
  int _playlistIndex = 0;
  bool _isDescriptionExpanded = false;

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
    
    _initIframeController(_activeVideoId);
    _loadVideoDetails();
    _loadRelatedVideos();
  }

  void _initIframeController(String videoId) {
    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        playsInline: true,
        showVideoAnnotations: false,
        enableCaption: false,
      ),
    );

    // Auto-advance / Loop listener
    _controller.listen((state) {
      if (state.playerState == PlayerState.ended) {
        _handleVideoEnded();
      }
    });
  }

  void _handleVideoEnded() {
    if (!_isAutoplay) return;

    if (_loopMode == PlaylistLoopMode.one) {
      _controller.seekTo(seconds: 0);
      _controller.playVideo();
      return;
    }

    if (_playlist.isNotEmpty) {
      if (_playlistIndex < _playlist.length - 1) {
        _selectVideoFromPlaylist(_playlistIndex + 1);
      } else if (_loopMode == PlaylistLoopMode.all) {
        _selectVideoFromPlaylist(0);
      }
    }
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
    _controller.loadVideoById(videoId: nextVid.id);
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
        setState(() {
          _video = Video.fromJson(response.data as Map<String, dynamic>);
        });
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
        setState(() {
          _relatedVideos = list
              .whereType<Map<String, dynamic>>()
              .map((v) => Video.fromJson(v))
              .where((v) => v.id != _activeVideoId)
              .take(10)
              .toList();
        });
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

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPlaylist = _playlist.isNotEmpty;

    return YoutubePlayerScaffold(
      controller: _controller,
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Top IFrame Player Container
                player,

                // Video Metadata & Recommendations Scrollable Area
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      // Video Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _video?.title ?? 'Loading video...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // View Count and Published Date
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${_video?.viewCount ?? 0} views',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // YouTube Playlist Watch Widget (Loop, Autoplay, Shuffle, Queue)
                      if (hasPlaylist)
                        YouTubePlaylistWidget(
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

                      // Channel Header (Avatar, Title, Subscribe Button)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            ChannelAvatar(
                              avatarUrl: _video?.channelAvatarUrl,
                              channelTitle: _video?.channelTitle ?? 'Channel',
                              radius: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _video?.channelTitle ?? 'Channel',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: theme.colorScheme.primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: () {
                                if (_video?.channelId.isNotEmpty == true) {
                                  _channelService.toggleSubscribe(_video!.channelId);
                                }
                              },
                              child: const Text('Subscribe'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action buttons row (Share, Save, YouTube App)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: () {
                                Share.share('${AppConfig.apiBaseUrl}/watch/$_activeVideoId');
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildActionButton(
                              icon: Icons.playlist_add,
                              label: 'Save',
                              onTap: () {
                                if (_video != null) {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (ctx) => VideoOptionsBottomSheet(video: _video!),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildActionButton(
                              icon: Icons.open_in_new,
                              label: 'Open YouTube',
                              onTap: _openInYouTubeApp,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Expandable Description Box
                      if (_video?.description != null && _video!.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: InkWell(
                            onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark ? Colors.grey.shade900 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _video!.description!,
                                    maxLines: _isDescriptionExpanded ? null : 3,
                                    overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
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
                      const SizedBox(height: 20),

                      // Related Videos Header & List
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Related Videos',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (_relatedVideos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: Text('No related videos found')),
                        )
                      else
                        ..._relatedVideos.map((rv) => RecommendationVideoCard(
                          video: rv,
                          onTap: () {
                            _controller.loadVideoById(videoId: rv.id);
                            setState(() {
                              _activeVideoId = rv.id;
                              _video = rv;
                            });
                            _loadVideoDetails();
                            _loadRelatedVideos();
                          },
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

  Widget _buildActionButton({required IconData icon, required String label, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
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
