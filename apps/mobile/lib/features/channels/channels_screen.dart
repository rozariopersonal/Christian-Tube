import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/channel_request.dart';
import '../../core/utils/formatters.dart';
import '../../shared/ui/channel_avatar.dart';
import '../auth/auth_service.dart';
import 'channel_service.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> with SingleTickerProviderStateMixin {
  final ChannelService _channelService = ChannelService();
  final AuthService _authService = AuthService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _channelService.loadSubscriptions();
    _channelService.fetchChannels();
    _channelService.fetchRequests();
    _authService.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAdmin = _authService.isAdmin;

    return AnimatedBuilder(
      animation: _channelService,
      builder: (context, _) {
        final channels = _channelService.channels;
        final requests = _channelService.channelRequests;
        final pendingRequests = requests.where((r) => r['status'] == 'PENDING').toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              isAdmin ? 'Channel Administration' : 'Subscriptions',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            actions: [
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF3B82F6)),
                  tooltip: 'Add Channel Directly',
                  onPressed: () => _showAddChannelDialog(context),
                )
              else
                TextButton.icon(
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Request Channel'),
                  onPressed: () => _showRequestChannelDialog(context),
                ),
            ],
            bottom: isAdmin
                ? TabBar(
                    controller: _tabController,
                    indicatorColor: theme.colorScheme.primary,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Channels'),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${channels.length}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Requests'),
                            if (pendingRequests.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${pendingRequests.length}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          body: isAdmin
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChannelsList(channels, isDark, isAdmin: true),
                    _buildRequestsList(requests, isDark),
                  ],
                )
              : _buildChannelsList(channels, isDark, isAdmin: false),
          floatingActionButton: !isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _showRequestChannelDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Request Channel'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildChannelsList(List<dynamic> channels, bool isDark, {required bool isAdmin}) {
    if (_channelService.isLoading && channels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.tv_off_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No channels added yet',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isAdmin
                    ? 'As an Admin, you can search and add channels directly.'
                    : 'Submit a channel request to get it approved by the administrator.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => isAdmin ? _showAddChannelDialog(context) : _showRequestChannelDialog(context),
                icon: Icon(isAdmin ? Icons.add : Icons.send),
                label: Text(isAdmin ? 'Add Channel' : 'Request Channel'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _channelService.fetchChannels(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ch = channels[index];
          final isSubscribed = ch.isSubscribed;

          return Container(
            padding: const EdgeInsets.all(14),
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
                  avatarUrl: ch.avatarUrl,
                  channelTitle: ch.name,
                  radius: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${Formatters.formatSubscribers(ch.subscriberCount)} subscribers • ${ch.videoCount} videos',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSubscribed
                        ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                        : const Color(0xFF3B82F6),
                    foregroundColor: isSubscribed
                        ? (isDark ? Colors.white70 : Colors.black87)
                        : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => _channelService.toggleSubscribe(ch.id),
                  icon: Icon(
                    isSubscribed ? Icons.notifications_active : Icons.add,
                    size: 16,
                  ),
                  label: Text(
                    isSubscribed ? 'Subscribed' : 'Subscribe',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (val) {
                      if (val == 'delete') {
                        _confirmDeleteChannel(context, ch.id, ch.name);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'delete',
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestsList(List<Map<String, dynamic>> requests, bool isDark) {
    if (_channelService.isLoadingRequests && requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No channel requests',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'When users request new channels, they will appear here for review.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _channelService.fetchRequests(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final req = requests[index];
          final id = req['id'] ?? '';
          final channelUrl = req['channelUrl'] ?? '';
          final notes = req['notes'] ?? '';
          final submittedBy = req['submittedBy'] ?? 'Anonymous';
          final status = req['status'] ?? 'PENDING';

          Color statusColor = Colors.amber;
          if (status == 'APPROVED') statusColor = Colors.green;
          if (status == 'REJECTED') statusColor = Colors.red;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        notes.isNotEmpty ? notes : channelUrl,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'URL: $channelUrl',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Requested by: $submittedBy',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                if (status == 'PENDING') ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _confirmRejectRequest(context, id),
                        icon: const Icon(Icons.close, color: Colors.red, size: 18),
                        label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final success = await _channelService.approveRequest(id, _authService.currentUser?.email);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? 'Channel approved & video ingestion started!' : 'Approval failed'),
                                backgroundColor: success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve & Ingest'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddChannelDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddChannelBottomSheet(
        onAddDirect: (url, name) async {
          final success = await _channelService.addChannel(
            channelUrl: url,
            name: name,
            adminEmail: _authService.currentUser?.email,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? 'Channel added successfully!' : 'Failed to add channel'),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          }
        },
        channelService: _channelService,
      ),
    );
  }

  void _showRequestChannelDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestChannelBottomSheet(
        onSubmitRequest: (url, name) async {
          final req = ChannelRequest(
            channelUrl: url,
            channelName: name,
            language: 'en',
            notes: name,
            createdAt: DateTime.now(),
          );
          final success = await _channelService.submitChannelRequest(req);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? 'Channel request submitted to admin!' : 'Failed to submit request'),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          }
        },
        channelService: _channelService,
      ),
    );
  }

  void _confirmDeleteChannel(BuildContext context, String channelId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Channel?'),
        content: Text('Are you sure you want to remove "$name"? All its videos will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _channelService.removeChannel(channelId);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _confirmRejectRequest(BuildContext context, String requestId) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Channel Request'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Reason for rejection (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _channelService.rejectRequest(requestId, reasonController.text.trim());
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

class _AddChannelBottomSheet extends StatefulWidget {
  final Function(String url, String name) onAddDirect;
  final ChannelService channelService;

  const _AddChannelBottomSheet({
    required this.onAddDirect,
    required this.channelService,
  });

  @override
  State<_AddChannelBottomSheet> createState() => _AddChannelBottomSheetState();
}

class _AddChannelBottomSheetState extends State<_AddChannelBottomSheet> {
  final TextEditingController _queryController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  void _performSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final results = await widget.channelService.searchYouTubeChannels(q.trim());
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Add Channel (Admin)', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryController,
            decoration: InputDecoration(
              hintText: 'Search YouTube channel or paste URL...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _performSearch(_queryController.text),
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onSubmitted: _performSearch,
          ),
          const SizedBox(height: 16),
          if (_queryController.text.trim().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ingest "${_queryController.text.trim()}" directly',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final input = _queryController.text.trim();
                      if (input.isNotEmpty) {
                        Navigator.pop(context);
                        widget.onAddDirect(input, input);
                      }
                    },
                    child: const Text('Add Now'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isSearching)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        'Search YouTube to directly ingest channels into the instance',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final r = _searchResults[idx];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: r['thumbnail'] != null ? NetworkImage(r['thumbnail']) : null,
                            child: r['thumbnail'] == null ? const Icon(Icons.tv) : null,
                          ),
                          title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(
                            r['handle'] != null ? '${r['handle']}' : (r['description'] != null ? '${r['description']}' : 'YouTube Channel'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onAddDirect(r['id'] ?? '', r['name'] ?? '');
                            },
                            child: const Text('Add'),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _RequestChannelBottomSheet extends StatefulWidget {
  final Function(String url, String name) onSubmitRequest;
  final ChannelService channelService;

  const _RequestChannelBottomSheet({
    required this.onSubmitRequest,
    required this.channelService,
  });

  @override
  State<_RequestChannelBottomSheet> createState() => _RequestChannelBottomSheetState();
}

class _RequestChannelBottomSheetState extends State<_RequestChannelBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  void _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final results = await widget.channelService.searchYouTubeChannels(q.trim());
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Request Channel', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Find a YouTube channel you would like the admin to approve and add to the platform:',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search YouTube channel or paste URL...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _search(_searchController.text),
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onSubmitted: _search,
          ),
          const SizedBox(height: 12),
          if (_isSearching)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text('Search for a YouTube channel above', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final r = _searchResults[idx];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: r['thumbnail'] != null ? NetworkImage(r['thumbnail']) : null,
                            child: r['thumbnail'] == null ? const Icon(Icons.tv) : null,
                          ),
                          title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(
                            '${Formatters.formatSubscribers(r['subscriberCount'])} subs',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onSubmitRequest(r['id'] ?? '', r['name'] ?? '');
                            },
                            child: const Text('Request'),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
