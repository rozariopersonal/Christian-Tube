import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api/api_client.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/models/channel.dart';
import '../../core/models/video.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/video_card.dart';
import 'channel_service.dart';

/// Mutually exclusive partition of a channel's videos into regular videos,
/// shorts, and live streams without dropping 1-hour+ sermons.
({List<Video> videos, List<Video> shorts, List<Video> streams})
    partitionChannelVideos(List<Video> allVideos) {
  final videos = <Video>[];
  final shorts = <Video>[];
  final streams = <Video>[];

  for (final v in allVideos) {
    final normalizedType = (v.type ?? 'VIDEO').trim().toUpperCase();
    final isStream =
        v.isLive || (v.duration ?? '').toLowerCase().contains('live');
    if (normalizedType == 'SHORT') {
      shorts.add(v);
    } else if (isStream) {
      streams.add(v);
    } else {
      videos.add(v);
    }
  }

  return (videos: videos, shorts: shorts, streams: streams);
}

class ChannelDetailScreen extends StatefulWidget {
  final String channelId;
  final ChannelService? channelService;
  final Dio? dio;

  const ChannelDetailScreen({
    super.key,
    required this.channelId,
    this.channelService,
    this.dio,
  });

  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen>
    with SingleTickerProviderStateMixin {
  late final ChannelService _channelService;
  late final Dio _dio;

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
    _channelService = widget.channelService ?? ChannelService();
    _dio = widget.dio ?? ApiClient().dio;
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _isLoadingVideos = true;
    });

    // Fetch Channel Details
    _channel = await _channelService.fetchChannelDetails(widget.channelId);

    // Fetch all videos (including shorts) for this channel
    if (_channel != null) {
      try {
        final response = await _dio.get('/api/videos', queryParameters: {
          'channelId': widget.channelId,
          'type': 'ALL',
          'limit': 200,
        });
        if (response.statusCode == 200 && response.data != null) {
          final List<dynamic> list = response.data is List
              ? response.data
              : (response.data['videos'] ?? []);
          final allVideos = list
              .whereType<Map>()
              .map((v) => Video.fromJson(Map<String, dynamic>.from(v)))
              .toList();
          final partitioned = partitionChannelVideos(allVideos);
          _videos = partitioned.videos;
          _shorts = partitioned.shorts;
          _streams = partitioned.streams;
        }
      } catch (e) {
        debugPrint('Error fetching channel videos: $e');
      }
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
    final tokens = context.tokens;

    if (_isLoading && _channel == null) {
      return Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(automaticallyImplyLeading: false),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_channel == null) {
      return Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(automaticallyImplyLeading: false),
        body: Center(
          child: MaxWidthBox(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.tv_off_outlined,
                  size: 64,
                  color: tokens.onSurfaceDisabled,
                ),
                const SizedBox(height: 16),
                Text(
                  'Channel not found',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: tokens.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This channel could not be loaded right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: tokens.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              automaticallyImplyLeading: false,
              expandedHeight: 120,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.4),
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
            _buildVideosTab(_streams),
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
    final statsLine = ch.subscriberCount > 0
        ? '${Formatters.formatSubscribers(ch.subscriberCount)} followers • ${ch.videoCount} videos'
        : '${ch.videoCount} videos';

    return MaxWidthBox(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ChannelAvatar(
            avatarUrl: ch.avatarUrl,
            channelTitle: ch.name,
            radius: 40,
          ),
          const SizedBox(height: 12),
          Text(
            ch.name,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            statsLine,
            textAlign: TextAlign.center,
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
          AnimatedBuilder(
            animation: _channelService,
            builder: (context, _) {
              final isFollowed = _channelService.isFollowed(ch.id);
              return ElevatedButton.icon(
                onPressed: () => _channelService.toggleFollow(ch.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isFollowed ? tokens.surfaceVariant : context.accent,
                  foregroundColor:
                      isFollowed ? tokens.onSurface : tokens.onScrim,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: Icon(isFollowed ? Icons.check : Icons.add, size: 18),
                label: Text(isFollowed ? 'Following' : 'Follow'),
              );
            },
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
        child: Text(
          'No videos found',
          style: TextStyle(color: context.tokens.onSurfaceMuted),
        ),
      );
    }

    final screenClass = ScreenClass.of(context);
    final isCompact = screenClass == ScreenClass.compact;

    return MaxWidthBox(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: isCompact ? 600 : 420,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isCompact ? 1.05 : 0.9,
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
        child: Text(
          'No shorts found',
          style: TextStyle(color: context.tokens.onSurfaceMuted),
        ),
      );
    }

    final tokens = context.tokens;

    return MaxWidthBox(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.56,
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
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.45, 1.0],
                          colors: [
                            tokens.scrim.withValues(alpha: 0.0),
                            tokens.scrim.withValues(alpha: 0.78),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onScrim,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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

    return MaxWidthBox(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Description',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (ch.description?.isNotEmpty ?? false)
                  ? ch.description!
                  : 'No description available.',
            ),
            const SizedBox(height: 32),
            Text(
              'Stats',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (ch.subscriberCount > 0) ...[
              Text('${Formatters.formatSubscribers(ch.subscriberCount)} followers'),
              const SizedBox(height: 8),
            ],
            Text('${ch.videoCount} videos'),
          ],
        ),
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
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
