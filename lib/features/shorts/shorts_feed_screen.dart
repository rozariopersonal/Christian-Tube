import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/models/short.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import 'native_shorts_player.dart';

class ShortsFeedScreen extends StatefulWidget {
  const ShortsFeedScreen({super.key});

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
      final response = await _apiClient.dio.get('/shorts/feed');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : response.data['shorts'] ?? [];
        setState(() {
          _shorts = list.map((s) => Short.fromJson(s)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching shorts: $e');
      setState(() => _isLoading = false);
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
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
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
              const Text('No Christian Shorts available', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _fetchShorts, child: const Text('Refresh')),
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

              // Right Action Bar (Like, Share, etc.)
              Positioned(
                right: 12,
                bottom: 80,
                child: Column(
                  children: [
                    _buildActionButton(Icons.thumb_up_alt_outlined, Formatters.formatViews(short.likeCount)),
                    const SizedBox(height: 16),
                    _buildActionButton(Icons.comment_outlined, 'Comments'),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      Icons.share_outlined,
                      'Share',
                      onTap: () => Share.share('Watch this Christian short: https://christian-tube-six.vercel.app/watch/${short.id}'),
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
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
