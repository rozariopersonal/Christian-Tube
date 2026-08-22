import 'package:flutter/material.dart';
import '../../core/models/channel_request.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import 'channel_service.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final ChannelService _channelService = ChannelService();

  @override
  void initState() {
    super.initState();
    _channelService.fetchChannels();
  }

  void _showAddChannelDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String selectedLang = 'en';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request a Christian Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Channel Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'YouTube Channel URL', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedLang,
              decoration: const InputDecoration(labelText: 'Language', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'hi', child: Text('Hindi (हिन्दी)')),
                DropdownMenuItem(value: 'ta', child: Text('Tamil (தமிழ்)')),
                DropdownMenuItem(value: 'te', child: Text('Telugu (తెలుగు)')),
                DropdownMenuItem(value: 'kn', child: Text('Kannada (ಕನ್ನಡ)')),
                DropdownMenuItem(value: 'ml', child: Text('Malayalam (മലയാളം)')),
              ],
              onChanged: (val) {
                if (val != null) selectedLang = val;
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                final req = ChannelRequest(
                  channelUrl: urlCtrl.text,
                  channelName: nameCtrl.text,
                  language: selectedLang,
                  createdAt: DateTime.now(),
                );
                Navigator.pop(ctx);
                final success = await _channelService.submitChannelRequest(req);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Channel request submitted for review!' : 'Submitted successfully!'),
                    ),
                  );
                }
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Christian Channels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Request Channel',
            onPressed: _showAddChannelDialog,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _channelService,
        builder: (context, _) {
          if (_channelService.isLoading && _channelService.channels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_channelService.channels.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tv_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No Christian channels registered yet.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _showAddChannelDialog,
                    child: const Text('Suggest a Channel'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _channelService.fetchChannels,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _channelService.channels.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final channel = _channelService.channels[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  leading: ChannelAvatar(
                    avatarUrl: channel.avatarUrl,
                    channelTitle: channel.title,
                    radius: 24,
                  ),
                  title: Text(
                    channel.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${Formatters.formatViews(channel.subscriberCount)} subscribers • ${channel.videoCount} videos',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: channel.isSubscribed ? Colors.grey.shade200 : null,
                      foregroundColor: channel.isSubscribed ? Colors.black87 : theme.colorScheme.primary,
                      side: BorderSide(color: theme.colorScheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () => _channelService.toggleSubscribe(channel.id),
                    child: Text(channel.isSubscribed ? 'Subscribed' : 'Subscribe'),
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
