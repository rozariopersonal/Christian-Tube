import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../core/api/api_client.dart';
import '../../core/models/video.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/recommendation_video_card.dart';
import '../../shared/ui/video_options_bottom_sheet.dart';
import 'widgets/create_short_bottom_sheet.dart';

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
  final ApiClient _apiClient = ApiClient();
  late final YoutubePlayerController _controller;
  Video? _video;
  List<Video> _relatedVideos = [];
  bool _isSubscribed = false;
  bool _isDescriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _video = widget.initialVideo;
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        mute: false,
        loop: false,
      ),
    );

    _controller.loadVideoById(videoId: widget.videoId);
    _fetchVideoDetails();
  }

  Future<void> _fetchVideoDetails() async {
    try {
      final response = await _apiClient.dio.get('/api/videos/${widget.videoId}');
      if (response.statusCode == 200 && response.data != null) {
        setState(() {
          _video = Video.fromJson(response.data);
        });
      }
    } catch (e) {
      debugPrint('Error fetching video details: $e');
    }

    try {
      final relatedRes = await _apiClient.dio.get('/api/videos/${widget.videoId}/related');
      if (relatedRes.statusCode == 200 && relatedRes.data != null) {
        final List<dynamic> list = relatedRes.data is List ? relatedRes.data : relatedRes.data['videos'] ?? [];
        setState(() {
          _relatedVideos = list.map((v) => Video.fromJson(v)).toList();
        });
      }
    } catch (_) {}
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
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Video Player
                player,

                // Content & Details Scrollable Area
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      // Video Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _video?.title ?? 'ChristianTube Video',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Views & Published Date
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${Formatters.formatViews(_video?.viewCount ?? 0)} views • ${Formatters.formatTimeAgo(_video?.publishedAt ?? DateTime.now())}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Channel Row + Subscribe Button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            ChannelAvatar(
                              avatarUrl: _video?.channelAvatarUrl,
                              channelTitle: _video?.channelTitle ?? '',
                              radius: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _video?.channelTitle ?? 'Christian Channel',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSubscribed ? Colors.grey.shade300 : theme.colorScheme.primary,
                                foregroundColor: _isSubscribed ? Colors.black87 : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              onPressed: () {
                                setState(() => _isSubscribed = !_isSubscribed);
                              },
                              child: Text(_isSubscribed ? 'Subscribed' : 'Subscribe'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action buttons row (Share, Clip, Save, etc.)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: () {
                                Share.share('https://christian-tube-six.vercel.app/watch/${widget.videoId}');
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
                          'Related Devotions & Videos',
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
