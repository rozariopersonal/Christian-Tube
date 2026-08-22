import 'package:flutter/material.dart';
import '../../core/models/channel_request.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import 'channel_service.dart';
import '../../core/config/app_config.dart';

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
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedCategory = AppConfig.defaultCategories.firstWhere((c) => c != 'All', orElse: () => 'General');
    String selectedLang = 'en';
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add ${AppConfig.appName} Channel',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter a YouTube channel handle or link (e.g. @veritasium, @3blue1brown, or youtube.com/@channel):',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'YouTube Channel Handle or URL *',
                      hintText: '@channel_handle or URL',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Channel Name (Optional)',
                      hintText: 'Auto-fetched if left blank',
                      prefixIcon: Icon(Icons.title),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                    items: AppConfig.defaultCategories
                        .where((c) => c != 'All')
                        .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedLang,
                    decoration: const InputDecoration(
                      labelText: 'Language',
                      prefixIcon: Icon(Icons.language),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'hi', child: Text('Hindi (हिन्दी)')),
                      DropdownMenuItem(value: 'ta', child: Text('Tamil (தமிழ்)')),
                      DropdownMenuItem(value: 'te', child: Text('Telugu (తెలుగు)')),
                      DropdownMenuItem(value: 'kn', child: Text('Kannada (ಕನ್ನಡ)')),
                      DropdownMenuItem(value: 'ml', child: Text('Malayalam (മലയാളം)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedLang = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final inputUrl = urlCtrl.text.trim();
                        if (inputUrl.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a channel handle or URL.')),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);

                        final success = await _channelService.addChannel(
                          channelUrl: inputUrl,
                          name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
                          category: selectedCategory,
                          language: selectedLang,
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? '🎉 Channel added! Initial video sync initiated.'
                                    : 'Channel request submitted for indexing.',
                              ),
                              backgroundColor: success ? Colors.green.shade700 : null,
                            ),
                          );
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(isSubmitting ? 'Adding...' : 'Add Channel'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${AppConfig.appName} Channels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Channel',
            onPressed: _showAddChannelDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddChannelDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Channel'),
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
                  Text('No ${AppConfig.appName} channels registered yet.'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddChannelDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Channel'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _channelService.fetchChannels,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
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
