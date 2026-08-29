import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/models/video.dart';
import '../../shared/ui/video_card.dart';
import '../channels/channel_service.dart';
import 'video_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final VideoService _videoService = VideoService();
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
    return AnimatedBuilder(
      animation: Listenable.merge([_videoService, _channelService]),
      builder: (context, _) {
        final tokens = context.tokens;
        final videos = _videoService.videos;
        final channels = _channelService.channels;
        final subscribedIds = _channelService.subscribedChannelIds;
        final subscribedChannels = channels.where((c) => subscribedIds.contains(c.id)).toList();

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    AppConfig.appName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, letterSpacing: -0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset(
                  'assets/logo.png',
                  height: 26,
                  width: 26,
                  errorBuilder: (_, __, ___) => Icon(Icons.play_circle_fill, color: context.primary),
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
                              ? tokens.onSurface
                              : tokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            subscribedChannels.isNotEmpty ? 'All Subscriptions' : 'All',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _selectedCategory == 'All' ? FontWeight.bold : FontWeight.w500,
                              color: _selectedCategory == 'All'
                                  ? tokens.surface
                                  : tokens.onSurfaceMuted,
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
                                  ? tokens.onSurface
                                  : tokens.surfaceVariant,
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
                                          ? tokens.surface
                                          : tokens.onSurfaceMuted,
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
                            color: tokens.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 16, color: tokens.onSurfaceMuted),
                              const SizedBox(width: 4),
                              Text(
                                'Explore Channels',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.onSurfaceMuted,
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
          body: _buildBody(videos, subscribedIds.isEmpty),
        );
      },
    );
  }

  Widget _buildBody(List<Video> videos, bool hasNoSubscriptions) {
    if (_videoService.isLoading && videos.isEmpty) {
      return Center(child: CircularProgressIndicator(color: context.primary));
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
                  color: context.tokens.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.subscriptions_outlined,
                  size: 56,
                  color: context.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your Feed is Empty',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.tokens.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Subscribe to channels in our curated library to build your personalized feed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.tokens.onSurfaceMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
              Icon(Icons.video_library_outlined, size: 56, color: context.tokens.onSurfaceMuted),
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
      color: context.primary,
      onRefresh: () async {
        await _channelService.loadSubscriptions();
        _videoService.updateSubscribedChannelIds(_channelService.subscribedChannelIds);
        await _videoService.refreshVideos();
      },
      child: ScreenClass.of(context).isCompact
          ? _buildFeedList(videos)
          : _buildFeedGrid(videos),
    );
  }

  Widget _buildFeedList(List<Video> videos) {
    return MaxWidthBox(
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: videos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == videos.length) {
            if (_videoService.hasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _buildAllCaughtUpFooter();
          }

          final video = videos[index];
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

  Widget _buildFeedGrid(List<Video> videos) {
    return MaxWidthBox(
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumnsFor(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 1.1,
        ),
        itemCount: videos.length + 1,
        itemBuilder: (context, index) {
          if (index == videos.length) {
            if (_videoService.hasMore) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final video = videos[index];
          return VideoGridCard(
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

  Widget _buildAllCaughtUpFooter() {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tokens.surfaceBorder,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 32,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "You're all caught up!",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "You've scrolled through all available videos from your subscribed channels.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: tokens.onSurfaceMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.onSurfaceMuted,
              side: BorderSide(color: tokens.surfaceBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => context.go('/channels'),
            icon: const Icon(Icons.explore_outlined, size: 16),
            label: const Text('Discover More Channels', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

