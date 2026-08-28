import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/app_config.dart';
import '../../core/models/short.dart';
import '../../core/models/video.dart';
import '../../shared/ui/video_card.dart';
import '../channels/channel_service.dart';
import '../shorts/shorts_service.dart';
import 'video_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final VideoService _videoService = VideoService();
  final ShortsService _shortsService = ShortsService();
  final ChannelService _channelService = ChannelService();
  final ScrollController _scrollController = ScrollController();

  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _channelService.addListener(_onChannelsChanged);
    _loadInitialFeed();
    _scrollController.addListener(_onScroll);
  }

  void _onChannelsChanged() {
    _videoService.updateSubscribedChannelIds(
      _channelService.subscribedChannelIds,
      triggerRefresh: true,
    );
  }

  Future<void> _loadInitialFeed() async {
    await _channelService.loadSubscriptions();
    await _channelService.fetchChannels();
    _videoService.updateSubscribedChannelIds(
      _channelService.subscribedChannelIds,
      triggerRefresh: true,
    );
    _shortsService.fetchShorts();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _videoService.fetchVideos();
    }
  }

  @override
  void dispose() {
    _channelService.removeListener(_onChannelsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([_videoService, _shortsService, _channelService]),
      builder: (context, _) {
        final videos = _videoService.videos;
        final shorts = _shortsService.shorts;
        final channels = _channelService.channels;
        final subscribedIds = _channelService.subscribedChannelIds;
        final subscribedChannels = channels.where((c) => subscribedIds.contains(c.id)).toList();

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 26,
                  width: 26,
                  errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_fill, color: Colors.red),
                ),
                const SizedBox(width: 8),
                Text(
                  AppConfig.appName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, letterSpacing: -0.5),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.cast_outlined),
                tooltip: 'Cast',
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none_outlined),
                tooltip: 'Notifications',
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search',
                onPressed: () => context.push('/search'),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.go('/profile'),
                  child: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.transparent,
                    child: Icon(Icons.account_circle, size: 28),
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  children: [
                    // "All" / "All Subscriptions" Pill
                    InkWell(
                      onTap: () {
                        setState(() => _selectedCategory = 'All');
                        _videoService.setFilter(
                          channelId: null,
                          onlySubscribed: subscribedIds.isNotEmpty,
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedCategory == 'All'
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? Colors.grey.shade900 : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            subscribedChannels.isNotEmpty ? 'All Subscriptions' : 'All',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _selectedCategory == 'All' ? FontWeight.bold : FontWeight.w500,
                              color: _selectedCategory == 'All'
                                  ? (isDark ? Colors.black : Colors.white)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Subscribed Channel Filter Pills (Avatar + Channel Name)
                    ...subscribedChannels.map((ch) {
                      final isSelected = _selectedCategory == ch.id;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedCategory = isSelected ? 'All' : ch.id);
                            _videoService.setFilter(
                              channelId: isSelected ? null : ch.id,
                              onlySubscribed: isSelected ? subscribedIds.isNotEmpty : false,
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? Colors.white : Colors.black)
                                  : (isDark ? Colors.grey.shade900 : Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ch.avatarUrl.isNotEmpty)
                                  ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: ch.avatarUrl,
                                      width: 18,
                                      height: 18,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(Icons.account_circle, size: 18),
                                    ),
                                  )
                                else
                                  const Icon(Icons.account_circle, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  ch.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? (isDark ? Colors.black : Colors.white)
                                        : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    // "+ Explore Channels" Pill if no subscriptions or to manage
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InkWell(
                        onTap: () => context.go('/channels'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 16, color: isDark ? Colors.white70 : Colors.black87),
                              const SizedBox(width: 4),
                              Text(
                                'Explore Channels',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: _buildBody(videos, shorts, isDark, subscribedIds.isEmpty),
        );
      },
    );
  }

  Widget _buildBody(List<Video> videos, List<Short> shorts, bool isDark, bool hasNoSubscriptions) {
    if (_videoService.isLoading && videos.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    if (hasNoSubscriptions) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.subscriptions_outlined,
                  size: 56,
                  color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your Feed is Empty',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Subscribe to channels in our curated library to build your personalized feed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => context.go('/channels'),
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: const Text('Explore Channels', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    if (videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_library_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No videos found for selected filter',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _selectedCategory = 'All');
                  _videoService.setFilter(channelId: null, onlySubscribed: true);
                },
                child: const Text('Show All Subscriptions'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.red,
      onRefresh: () async {
        await _channelService.loadSubscriptions();
        _videoService.updateSubscribedChannelIds(_channelService.subscribedChannelIds);
        await _videoService.refreshVideos();
        await _shortsService.fetchShorts();
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: videos.length + (_videoService.hasMore ? 1 : 0) + (shorts.isNotEmpty ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          // Shorts Shelf insertion at position 3
          if (shorts.isNotEmpty && index == 3) {
            return _buildShortsShelf(shorts, isDark);
          }

          final videoIndex = shorts.isNotEmpty && index > 3 ? index - 1 : index;

          if (videoIndex == videos.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: Colors.red)),
            );
          }

          final video = videos[videoIndex];
          return VideoCard(
            video: video,
            onTap: () {
              context.push('/watch/${video.id}', extra: {
                'video': video,
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildShortsShelf(List<Short> shorts, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.bolt, color: Colors.red, size: 24),
                SizedBox(width: 6),
                Text(
                  'Shorts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: shorts.length > 8 ? 8 : shorts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final short = shorts[index];
                return InkWell(
                  onTap: () {
                    context.go('/shorts?id=${short.id}', extra: {
                      'shortId': short.id,
                      'initialIndex': index,
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 135,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: short.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: Colors.grey.shade800),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.6, 1.0],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Text(
                            short.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

