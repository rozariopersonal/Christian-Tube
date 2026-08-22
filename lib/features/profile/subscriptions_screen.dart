import 'package:flutter/material.dart';
import '../../shared/ui/channel_avatar.dart';
import '../channels/channel_service.dart';

class SubscriptionsScreen extends StatelessWidget {
  final ChannelService channelService;

  const SubscriptionsScreen({super.key, required this.channelService});

  @override
  Widget build(BuildContext context) {
    final subs = channelService.channels.where((c) => c.isSubscribed).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      body: subs.isEmpty
          ? const Center(child: Text('You have not subscribed to any channels yet.'))
          : ListView.builder(
              itemCount: subs.length,
              itemBuilder: (context, index) {
                final channel = subs[index];
                return ListTile(
                  leading: ChannelAvatar(avatarUrl: channel.avatarUrl, channelTitle: channel.title),
                  title: Text(channel.title),
                  subtitle: Text('${channel.subscriberCount} subscribers'),
                  trailing: TextButton(
                    onPressed: () => channelService.toggleSubscribe(channel.id),
                    child: const Text('Unsubscribe'),
                  ),
                );
              },
            ),
    );
  }
}
