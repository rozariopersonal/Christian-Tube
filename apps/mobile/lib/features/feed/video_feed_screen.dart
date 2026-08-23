import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/video.dart';
import '../../shared/ui/channel_avatar.dart';
import '../../shared/ui/video_card.dart';
import '../channels/channel_service.dart';
import 'video_service.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final VideoService _videoService = VideoService();
  final ChannelService _channelService = ChannelService();
  final ScrollController _scrollController = ScrollController();

  String? _activeChannelFilter;

  @override
  void initState() {
    super.initState();
    _loadInitialFeed();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadInitialFeed() async {
    await _channelService.loadSubscriptions();
    await _channelService.fetchChannels();
    _videoService.updateSubscribedChannelIds(_channelService.subscribedChannelIds);
    _videoService.refreshVideos();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _videoService.fetchVideos();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([_videoService, _channelService]),
      builder: (context, _) {
        final videos = _videoService.videos;
        final channels = _channelService.channels;
        final subscribedIds = _channelService.subscribedChannelIds;
        final subscribedChannels = channels.where((c) => subscribedIds.contains(c.id)).toList();

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset('assets/logo.png', height: 26, width: 26, errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_fill, color: Colors.blue)),
                const SizedBox(width: 8),
                const Text('Home Feed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => context.push('/search'),
              ),
            ],
            bottom: subscribedChannels.isNotEmpty
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(56),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          // "All Subscriptions" Pill
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: const Text('All Subscriptions'),
                              selected: _activeChannelFilter == null,
                              onSelected: (selected) {
                                setState(() => _activeChannelFilter = null);
                                _videoService.setFilter(channelId: null, onlySubscribed: true);
                              },
                            ),
                          ),

                          // Channel Avatar Filter Pills
                          ...subscribedChannels.map((ch) {
                            final isSelected = _activeChannelFilter == ch.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                avatar: ChannelAvatar(avatarUrl: ch.avatarUrl, channelTitle: ch.name, radius: 12),
                                label: Text(ch.name),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() => _activeChannelFilter = selected ? ch.id : null);
                                  _videoService.setFilter(
                                    channelId: selected ? ch.id : null,
                                    onlySubscribed: !selected,
                                  );
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          body: _buildBody(videos, subscribedIds.isEmpty, isDark),
        );
      },
    );
  }

  Widget _buildBody(List<Video> videos, bool hasNoSubscriptions, bool isDark) {
    if (hasNoSubscriptions) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.subscriptions_outlined, size: 56, color: Colors.blue),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Subscriptions Yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your home feed displays the latest videos exclusively from channels you subscribe to.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => context.go('/channels'),
                icon: const Icon(Icons.explore),
                label: const Text('Browse Channels & Subscribe'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videoService.isLoading && videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No videos found from your subscribed channels.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _videoService.refreshVideos(),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _channelService.loadSubscriptions();
        _videoService.updateSubscribedChannelIds(_channelService.subscribedChannelIds);
        await _videoService.refreshVideos();
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: videos.length + (_videoService.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (index == videos.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final video = videos[index];
          return VideoCard(
            video: video,
            onTap: () {
              context.push('/watch/${video.id}', extra: {
                'video': video,
                'playlist': videos,
                'playlistTitle': 'Home Feed',
                'initialIndex': index,
              });
            },
          );
        },
      ),
    );
  }
}
