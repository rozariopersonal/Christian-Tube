import 'package:flutter/material.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../channels/channel_service.dart';

class SubscriptionsScreen extends StatelessWidget {
  final ChannelService channelService;

  const SubscriptionsScreen({super.key, required this.channelService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                    Icon(Icons.subscriptions_outlined, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No Subscriptions',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Browse the Channels tab to find and subscribe to channels.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: subs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final channel = subs[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
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
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade400,
                        side: BorderSide(color: Colors.red.shade300),
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
          );
        },
      ),
    );
  }
}
