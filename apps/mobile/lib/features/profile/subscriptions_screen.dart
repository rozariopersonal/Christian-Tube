import 'package:flutter/material.dart';
import '../../core/utils/formatters.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/layout/content_width.dart';
import '../../shared/ui/channel_avatar.dart';
import '../channels/channel_service.dart';

class SubscriptionsScreen extends StatelessWidget {
  final ChannelService channelService;

  const SubscriptionsScreen({super.key, required this.channelService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
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
                    Icon(Icons.subscriptions_outlined, size: 56, color: context.tokens.onSurfaceDisabled),
                    const SizedBox(height: 16),
                    const Text(
                      'No Subscriptions',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Browse the Channels tab to find and subscribe to channels.',
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
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final channel = subs[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.tokens.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: context.tokens.surfaceBorder,
                  ),
                ),
                child: Row(
                  children: [
                    ChannelAvatar(
                      avatarUrl: channel.avatarUrl,
                      channelTitle: channel.title,
                      radius: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${Formatters.formatSubscribers(channel.subscriberCount)} subscribers',
                            style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(color: Theme.of(context).colorScheme.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => channelService.toggleSubscribe(channel.id),
                      child: const Text('Unsubscribe', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
            ),
          );
        },
      ),
    );
  }
}
