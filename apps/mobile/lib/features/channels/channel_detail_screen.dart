import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/video.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/video_card.dart';
import 'channel_service.dart';

class ChannelDetailScreen extends StatefulWidget {
  final String channelId;

  const ChannelDetailScreen({super.key, required this.channelId});

  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen>
    with SingleTickerProviderStateMixin {
  final ChannelService _channelService = ChannelService();
  final ApiClient _apiClient = ApiClient();
  
  late TabController _tabController;
  Channel? _channel;
  bool _isLoading = true;

  List<Video> _videos = [];
  List<Video> _shorts = [];
  List<Video> _streams = [];
  
  bool _isLoadingVideos = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // Fetch Channel Details
    _channel = await _channelService.fetchChannelDetails(widget.channelId);
    
    // Fetch all videos for this channel
    try {
      final response = await _apiClient.dio.get('/api/videos', queryParameters: {
        'channelId': widget.channelId,
        'limit': 200, // fetch a good batch initially
      });
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : (response.data['videos'] ?? []);
        final allVideos = list.map((v) => Video.fromJson(v)).toList();
        
        _videos = allVideos.where((v) => v.type == 'VIDEO' && !((v.duration ?? '').contains('Live') || (v.duration ?? '').length > 5 && (v.duration ?? '').startsWith('1:'))).toList();
        _shorts = allVideos.where((v) => v.type == 'SHORT').toList();
        
        // Very basic heuristic for streams if not strictly tagged in db: long videos > 1 hr or tagged streams
        _streams = allVideos.where((v) => v.type == 'VIDEO' && (v.duration ?? '').split(':').length == 3).toList();
      }
    } catch (e) {
      debugPrint('Error fetching channel videos: $e');
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingVideos = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _channel == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        tokens.background,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildChannelHeader(context),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  labelColor: tokens.onSurface,
                  unselectedLabelColor: tokens.onSurfaceMuted,
                  tabs: const [
                    Tab(text: 'Videos'),
                    Tab(text: 'Shorts'),
                    Tab(text: 'Live'),
                    Tab(text: 'About'),
                  ],
                ),
                color: tokens.background,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildVideosTab(_videos),
            _buildShortsTab(_shorts),
            _buildVideosTab(_streams), // Streams use standard video cards
            _buildAboutTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelHeader(BuildContext context) {
    if (_channel == null) return const SizedBox.shrink();
    
    final ch = _channel!;
    final tokens = context.tokens;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ChannelAvatar(avatarUrl: ch.avatarUrl, channelTitle: ch.name, radius: 40),
          const SizedBox(height: 12),
          Text(
            ch.name,
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: tokens.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '@${ch.name.replaceAll(' ', '').toLowerCase()} • ${Formatters.formatSubscribers(ch.subscriberCount)} subscribers • ${ch.videoCount} videos',
            style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          if (ch.description?.isNotEmpty ?? false) ...[
            Text(
              ch.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 16),
          ],
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _channelService.toggleSubscribe(ch.id);
                _channel = ch.copyWith(isSubscribed: !ch.isSubscribed);
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ch.isSubscribed ? tokens.surfaceVariant : Theme.of(context).colorScheme.primary,
              foregroundColor: ch.isSubscribed ? tokens.onSurface : Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: Icon(ch.isSubscribed ? Icons.notifications_active : Icons.add_alert),
            label: Text(ch.isSubscribed ? 'Subscribed' : 'Subscribe'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildVideosTab(List<Video> videoList) {
    if (_isLoadingVideos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (videoList.isEmpty) {
      return Center(
        child: Text('No videos found', style: TextStyle(color: context.tokens.onSurfaceMuted)),
      );
    }

    final screenClass = ScreenClass.of(context);
    final isCompact = screenClass == ScreenClass.compact;
    final crossAxisCount = isCompact ? 1 : (screenClass == ScreenClass.medium ? 2 : 3);

    return MaxWidthBox(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isCompact ? 1.2 : 0.9,
        ),
        itemCount: videoList.length,
        itemBuilder: (context, index) {
          return VideoCard(video: videoList[index]);
        },
      ),
    );
  }

  Widget _buildShortsTab(List<Video> shortsList) {
    if (_isLoadingVideos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shortsList.isEmpty) {
      return Center(
        child: Text('No shorts found', style: TextStyle(color: context.tokens.onSurfaceMuted)),
      );
    }

    return MaxWidthBox(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.56, // 9:16 approx
        ),
        itemCount: shortsList.length,
        itemBuilder: (context, index) {
          final video = shortsList[index];
          return GestureDetector(
            onTap: () {
              context.push('/watch/${video.id}', extra: video);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAboutTab() {
    if (_channel == null) return const SizedBox.shrink();
    final ch = _channel!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Description', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text((ch.description?.isNotEmpty ?? false) ? ch.description! : 'No description available.'),
          const SizedBox(height: 32),
          Text('Stats', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('${Formatters.formatSubscribers(ch.subscriberCount)} subscribers'),
          const SizedBox(height: 8),
          Text('${ch.videoCount} videos'),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, {required this.color});

  final TabBar _tabBar;
  final Color color;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: color,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
