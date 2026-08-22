import 'package:flutter/material.dart';
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

  void _showAddChannelModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddChannelModal(channelService: _channelService),
    );
  }

  void _confirmDeleteChannel(String channelId, String channelName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Channel?'),
        content: Text(
          'Are you sure you want to remove "$channelName" from ${AppConfig.appName}? Its indexed videos will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _channelService.removeChannel(channelId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Channel removed.' : 'Failed to remove channel.'),
                  ),
                );
              }
            },
            child: const Text('Remove'),
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
        title: Text('${AppConfig.appName} Channels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search & Add Channels',
            onPressed: _showAddChannelModal,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Channel',
            onPressed: _showAddChannelModal,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddChannelModal,
        icon: const Icon(Icons.add),
        label: const Text('Search & Add'),
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
                    onPressed: _showAddChannelModal,
                    icon: const Icon(Icons.search),
                    label: const Text('Search & Add YouTube Channels'),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: channel.isSubscribed ? Colors.grey.shade200 : null,
                          foregroundColor: channel.isSubscribed ? Colors.black87 : theme.colorScheme.primary,
                          side: BorderSide(color: theme.colorScheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () => _channelService.toggleSubscribe(channel.id),
                        child: Text(channel.isSubscribed ? 'Subscribed' : 'Subscribe'),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (val) {
                          if (val == 'remove') {
                            _confirmDeleteChannel(channel.id, channel.title);
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Text('Remove Channel', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
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

class _AddChannelModal extends StatefulWidget {
  final ChannelService channelService;

  const _AddChannelModal({required this.channelService});

  @override
  State<_AddChannelModal> createState() => _AddChannelModalState();
}

class _AddChannelModalState extends State<_AddChannelModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _selectedCategory = AppConfig.defaultCategories.firstWhere((c) => c != 'All', orElse: () => 'General');
  String _selectedLang = 'en';
  String? _addingId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _performYouTubeSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final results = await widget.channelService.searchYouTubeChannels(query.trim());
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _addChannelDirect(String channelIdOrUrl, String name, String? avatar) async {
    setState(() => _addingId = channelIdOrUrl);
    final ok = await widget.channelService.addChannel(
      channelUrl: channelIdOrUrl,
      name: name,
      category: _selectedCategory,
      language: _selectedLang,
    );

    if (mounted) {
      setState(() => _addingId = null);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '🎉 Added "$name"! Videos syncing now.' : 'Failed to add channel.'),
          backgroundColor: ok ? Colors.green.shade700 : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.search), text: 'Search YouTube'),
              Tab(icon: Icon(Icons.link), text: 'Paste Link / Handle'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: Search YouTube Channels
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'e.g. Veritasium, 3Blue1Brown, Khan Academy...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchResults = []);
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onSubmitted: _performYouTubeSearch,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _performYouTubeSearch(_searchCtrl.text),
                            child: const Text('Search'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isSearching)
                        const Expanded(child: Center(child: CircularProgressIndicator()))
                      else if (_searchResults.isEmpty)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.youtube_searched_for, size: 54, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                const Text('Search any YouTube channel to add it immediately.'),
                              ],
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (ctx, idx) {
                              final item = _searchResults[idx];
                              final id = item['id'] as String? ?? '';
                              final name = item['name'] as String? ?? 'Channel';
                              final thumb = item['thumbnail'] as String?;
                              final subs = item['subscriberCount'] as int?;
                              final isAddingThis = _addingId == id;

                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundImage: thumb != null ? NetworkImage(thumb) : null,
                                  child: thumb == null ? Text(name.isNotEmpty ? name[0] : 'C') : null,
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Text(
                                  subs != null ? '${Formatters.formatViews(subs)} subscribers' : (item['handle'] ?? ''),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: isAddingThis ? null : () => _addChannelDirect(id, name, thumb),
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  child: isAddingThis
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('+ Add'),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // TAB 2: Direct Link / Handle Input
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paste a YouTube URL or channel handle:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _urlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Channel URL or @Handle *',
                          hintText: 'https://youtube.com/@channel or @handle',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Channel Name (Optional)',
                          hintText: 'Auto-fetched if left blank',
                          prefixIcon: Icon(Icons.title),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
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
                          if (val != null) setState(() => _selectedCategory = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedLang,
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
                          if (val != null) setState(() => _selectedLang = val);
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_urlCtrl.text.trim().isNotEmpty) {
                              _addChannelDirect(
                                _urlCtrl.text.trim(),
                                _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : _urlCtrl.text.trim(),
                                null,
                              );
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Channel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
