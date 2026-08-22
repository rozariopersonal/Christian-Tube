import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/app_config.dart';
import '../../core/models/video.dart';
import '../../core/models/channel.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/shimmer_video_card.dart';
import '../../shared/ui/video_card.dart';
import '../../shared/ui/channel_avatar.dart';
import '../channels/channel_service.dart';
import '../update/update_service.dart';
import 'video_service.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final VideoService _videoService = VideoService();
  final ChannelService _channelService = ChannelService();

  @override
  void initState() {
    super.initState();
    _channelService.fetchChannels();
    _channelService.loadSubscriptions();
    _videoService.updateSubscribedChannelIds(_channelService.subscribedChannelIds);
    _videoService.fetchFeed();
    _checkAppUpdates();
  }

  Future<void> _checkAppUpdates() async {
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      UpdateService.showUpdatePopup(context, update);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 28, errorBuilder: (ctx, _, __) => const Icon(Icons.play_circle_fill, color: Colors.blue)),
            const SizedBox(width: 8),
            Text(
              AppConfig.appName,
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([_videoService, _channelService]),
        builder: (context, _) {
          _videoService.updateSubscribedChannelIds(_channelService.subscribedChannelIds);

          final channels = _channelService.channels;

          return RefreshIndicator(
            onRefresh: () async {
              await _channelService.fetchChannels();
              await _videoService.fetchFeed(refresh: true);
            },
            child: CustomScrollView(
              slivers: [
                // 1. Channel Filter Bar
                if (channels.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          // "All" Pill
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('All Channels'),
                              selected: _videoService.selectedChannelId == null && !_videoService.subscribedOnly,
                              onSelected: (_) => _videoService.selectChannel(null),
                              selectedColor: theme.colorScheme.primary,
                              labelStyle: TextStyle(
                                color: (_videoService.selectedChannelId == null && !_videoService.subscribedOnly)
                                    ? Colors.white
                                    : theme.textTheme.bodyMedium?.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),

                          // "Subscribed" Pill
                          if (_channelService.subscribedChannelIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                                label: const Text('Subscribed'),
                                selected: _videoService.subscribedOnly,
                                onSelected: (_) => _videoService.toggleSubscribedOnly(),
                                selectedColor: theme.colorScheme.primary,
                                labelStyle: TextStyle(
                                  color: _videoService.subscribedOnly
                                      ? Colors.white
                                      : theme.textTheme.bodyMedium?.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                          // Individual Channel Avatars
                          ...channels.map((ch) {
                            final isSelected = _videoService.selectedChannelId == ch.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: ChannelAvatar(
                                  avatarUrl: ch.thumbnail,
                                  channelTitle: ch.name,
                                  radius: 10,
                                ),
                                label: Text(ch.name),
                                selected: isSelected,
                                onSelected: (_) {
                                  _videoService.selectChannel(isSelected ? null : ch.id);
                                },
                                selectedColor: theme.colorScheme.primary,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                // 2. Category Filter Chips
                SliverToBoxAdapter(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      itemCount: _videoService.categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = _videoService.categories[index];
                        final isSelected = _videoService.selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) => _videoService.selectCategory(cat),
                          selectedColor: theme.colorScheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Content
                if (_videoService.isLoading && _videoService.videos.isEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const ShimmerVideoCard(),
                      childCount: 4,
                    ),
                  )
                else if (_videoService.errorMessage != null && _videoService.videos.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(_videoService.errorMessage!),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _videoService.fetchFeed(refresh: true),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_videoService.videos.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_library_outlined, size: 54, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(l10n.noVideosFound),
                          const SizedBox(height: 8),
                          if (_videoService.selectedChannelId != null || _videoService.subscribedOnly)
                            TextButton(
                              onPressed: () => _videoService.selectChannel(null),
                              child: const Text('Show All Channels'),
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final Video video = _videoService.videos[index];
                        return VideoCard(video: video);
                      },
                      childCount: _videoService.videos.length,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
