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
import 'widgets/create_short_bottom_sheet.dart';
import '../../core/config/app_config.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final Video? initialVideo;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    this.initialVideo,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  final ApiClient _apiClient = ApiClient();
  final ChannelService _channelService = ChannelService();

  Video? _video;
  List<Video> _relatedVideos = [];
  bool _isLoading = true;
  bool _isDescriptionExpanded = false;
  bool _hasPlayerError = false;

  @override
  void initState() {
    super.initState();
    _video = widget.initialVideo;
    _initPlayer(widget.videoId);
    _loadVideoDetails();
    _loadRelatedVideos();
  }

  void _initPlayer(String videoId) {
    _hasPlayerError = false;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        showVideoAnnotations: false,
        playsInline: true,
        enableCaption: true,
        strictRelatedVideos: false,
      ),
    );

    _controller.listen((event) {
      if (event.error != YoutubeError.none && event.error != YoutubeError.unknown) {
        if (mounted) {
          setState(() => _hasPlayerError = true);
        }
      }
    });
  }

  Future<void> _loadVideoDetails() async {
    try {
      dynamic response;
      try {
        response = await _apiClient.dio.get('/api/videos/${widget.videoId}');
      } catch (_) {
        response = await _apiClient.dio.get('/videos/${widget.videoId}');
      }

      if (response.statusCode == 200 && response.data != null) {
        setState(() {
          _video = Video.fromJson(response.data as Map<String, dynamic>);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading video details: $e');
      setState(() => _isLoading = false);
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
              .where((v) => v.id != widget.videoId)
              .take(10)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading related videos: $e');
    }
  }

  Future<void> _openInYouTubeApp() async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}');
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

    return YoutubePlayerScaffold(
      controller: _controller,
      builder: (context, player) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Top Video Player Container
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      player,
                      if (_hasPlayerError)
                        Container(
                          color: Colors.black87,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.info_outline, color: Colors.amber, size: 36),
                              const SizedBox(height: 8),
                              const Text(
                                'Playback restricted in embedded player.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _openInYouTubeApp,
                                icon: const Icon(Icons.play_circle_fill, color: Colors.red),
                                label: const Text('Play on YouTube'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

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

                      // Action buttons row (Share, Clip, Save, YouTube App)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: () {
                                Share.share('${AppConfig.apiBaseUrl}/watch/${widget.videoId}');
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildActionButton(
                              icon: Icons.cut,
                              label: 'Clip',
                              onTap: () {
                                if (_video != null) {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (ctx) => CreateShortBottomSheet(video: _video!),
                                  );
                                }
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
                              _video = rv;
                              _hasPlayerError = false;
                            });
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
