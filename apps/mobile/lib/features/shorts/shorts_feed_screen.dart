import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import 'native_shorts_player.dart';
import '../../core/config/app_config.dart';

class ShortsFeedScreen extends StatefulWidget {
  const ShortsFeedScreen({super.key});

  static final List<Short> seedShorts = [
    Short(
      id: 'gM7nJ3u8LBs',
      title: 'Trust In The Lord With All Your Heart | Daily Inspiration',
      videoUrl: 'https://www.youtube.com/shorts/gM7nJ3u8LBs',
      thumbnailUrl: 'https://img.youtube.com/vi/gM7nJ3u8LBs/hqdefault.jpg',
      channelId: 'christian_tube',
      channelTitle: 'Christian Life',
      viewCount: 14200,
      likeCount: 1850,
      publishedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Short(
      id: 'jL_TfP2qD_c',
      title: 'Jesus Is Always With You 🙏 Amen!',
      videoUrl: 'https://www.youtube.com/shorts/jL_TfP2qD_c',
      thumbnailUrl: 'https://img.youtube.com/vi/jL_TfP2qD_c/hqdefault.jpg',
      channelId: 'christian_tube',
      channelTitle: 'Daily Grace',
      viewCount: 28400,
      likeCount: 3900,
      publishedAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    Short(
      id: 'M6Q0pD54kYQ',
      title: 'Peace That Surpasses All Understanding ✨',
      videoUrl: 'https://www.youtube.com/shorts/M6Q0pD54kYQ',
      thumbnailUrl: 'https://img.youtube.com/vi/M6Q0pD54kYQ/hqdefault.jpg',
      channelId: 'christian_tube',
      channelTitle: 'Faith & Hope',
      viewCount: 19500,
      likeCount: 2400,
      publishedAt: DateTime.now().subtract(const Duration(days: 6)),
    ),
  ];

  @override
  State<ShortsFeedScreen> createState() => _ShortsFeedScreenState();
}

class _ShortsFeedScreenState extends State<ShortsFeedScreen> {
  final ApiClient _apiClient = ApiClient();
  final PageController _pageController = PageController();
  List<Short> _shorts = [];
  bool _isLoading = true;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchShorts();
  }

  Future<void> _fetchShorts() async {
    try {
      // 1. First attempt: Query /videos?type=SHORT
      final response = await _apiClient.dio.get('/videos?type=SHORT');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list =
            response.data is List ? response.data : response.data['shorts'] ?? [];
        if (list.isNotEmpty) {
          setState(() {
            _shorts = list.map((s) => Short.fromJson(s)).toList();
            _isLoading = false;
          });
          return;
        }
      }

      // 2. Fallback: Query all /videos and classify on frontend using Short.isShort
      final allResponse = await _apiClient.dio.get('/videos');
      if (allResponse.statusCode == 200 && allResponse.data != null) {
        final dynamic raw = allResponse.data;
        final List<dynamic> list =
            raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        final detected = list
            .whereType<Map<String, dynamic>>()
            .where(Short.isShort)
            .map((s) => Short.fromJson(s))
            .toList();

        if (detected.isNotEmpty) {
          setState(() {
            _shorts = detected;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _shorts = ShortsFeedScreen.seedShorts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching shorts, falling back to seed shorts: $e');
      setState(() {
        _shorts = ShortsFeedScreen.seedShorts;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF59E0B),
          ),
        ),
      );
    }

    if (_shorts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.movie_outlined, size: 64, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                'No ${AppConfig.appName} Shorts available',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _fetchShorts,
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _shorts.length,
        onPageChanged: (index) {
          setState(() => _currentPage = index);
        },
        itemBuilder: (context, index) {
          final short = _shorts[index];
          final isPlaying = index == _currentPage;

          return Stack(
            fit: StackFit.expand,
            children: [
              NativeShortsPlayer(short: short, isPlaying: isPlaying),

              // Gradient Overlay for readability
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black38,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black87,
                        ],
                        stops: [0.0, 0.2, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Right Action Bar (Like, Share, etc.)
              Positioned(
                right: 12,
                bottom: 80,
                child: Column(
                  children: [
                    _buildActionButton(Icons.thumb_up_alt_outlined,
                        Formatters.formatViews(short.likeCount)),
                    const SizedBox(height: 16),
                    _buildActionButton(Icons.comment_outlined, 'Comments'),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      Icons.share_outlined,
                      'Share',
                      onTap: () => Share.share(
                          'Watch this ${AppConfig.appName} Short: https://www.youtube.com/shorts/${short.id}'),
                    ),
                  ],
                ),
              ),

              // Bottom Info (Channel + Title)
              Positioned(
                left: 16,
                right: 70,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ChannelAvatar(
                          avatarUrl: short.channelAvatarUrl,
                          channelTitle: short.channelTitle,
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '@${short.channelTitle}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      short.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
