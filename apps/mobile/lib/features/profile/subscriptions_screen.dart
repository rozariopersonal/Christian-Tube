import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/layout/content_width.dart';
import '../../shared/ui/channel_follow_tile.dart';
import '../channels/channel_detail_screen.dart';
import '../channels/channel_service.dart';

class SubscriptionsScreen extends StatelessWidget {
  final ChannelService channelService;

  const SubscriptionsScreen({super.key, required this.channelService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Followed Channels'),
        automaticallyImplyLeading: false,
      ),
      body: AnimatedBuilder(
        animation: channelService,
        builder: (context, _) {
          final subscribedIds = channelService.subscribedChannelIds;
          final subs = channelService.channels.where((c) => subscribedIds.contains(c.id)).toList();

          if (subs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 56, color: context.tokens.onSurfaceDisabled),
                    const SizedBox(height: 16),
                    const Text(
                      'No Followed Channels',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Browse the Channels tab to discover and follow channels.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return MaxWidthBox(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: subs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final channel = subs[index];
                return ChannelFollowTile(
                  channelId: channel.id,
                  title: channel.title,
                  avatarUrl: channel.avatarUrl,
                  subscriberCount: channel.subscriberCount,
                  videoCount: channel.videoCount,
                  isFollowed: true,
                  onToggleFollow: () => channelService.toggleFollow(channel.id),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChannelDetailScreen(channelId: channel.id),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
