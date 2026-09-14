import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/ui/channel_avatar.dart';
import '../../auth/auth_service.dart';
import '../channel_detail_screen.dart';
import '../channel_service.dart';
import '../widgets/add_channel_sheet.dart';

class AdminChannelsScreen extends StatefulWidget {
  final ChannelService? channelService;
  const AdminChannelsScreen({super.key, this.channelService});

  @override
  State<AdminChannelsScreen> createState() => _AdminChannelsScreenState();
}

class _AdminChannelsScreenState extends State<AdminChannelsScreen> with SingleTickerProviderStateMixin {
  late final ChannelService _channelService = widget.channelService ?? ChannelService();
  final AuthService _authService = AuthService();
  late TabController _tabController;

  String _searchQuery = '';
  final Set<String> _ingestingChannels = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _channelService.fetchChannels();
    _channelService.fetchRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddChannelDialog(BuildContext context) {
    showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddChannelBottomSheet(
        onAddDirect: (url, name) async {
          setState(() => _ingestingChannels.add(name));
          final success = await _channelService.addChannel(
            channelUrl: url,
            name: name,
            adminEmail: _authService.currentUser?.email,
          );
          if (mounted) {
            setState(() => _ingestingChannels.remove(name));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? 'Channel added successfully!' : 'Failed to add channel'),
                backgroundColor: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
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
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _channelService,
      builder: (context, _) {
        final channels = _channelService.channels;
        final requests = _channelService.channelRequests;
        final pendingRequests = requests.where((r) => r['status'] == 'PENDING').toList();
        
        final filteredChannels = channels.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

        return Scaffold(
          appBar: AppBar(
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Channel Administration',
                maxLines: 1,
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                tooltip: 'Add Channel Directly',
                onPressed: () => _showAddChannelDialog(context),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Theme.of(context).colorScheme.primary,
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
                          color: context.tokens.surfaceVariant,
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
                            color: context.tokens.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${pendingRequests.length}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.tokens.onSurface),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildChannelsTab(filteredChannels, channels.length, pendingRequests.length),
              _buildRequestsTab(requests),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelsTab(List<dynamic> filteredChannels, int totalChannels, int pendingRequests) {
    return Column(
      children: [
        // Quick Stats Header
        Container(
          padding: const EdgeInsets.all(16),
          color: context.tokens.surfaceVariant.withValues(alpha: 0.3),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard('Total Channels', totalChannels.toString(), Icons.tv),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard('Pending', pendingRequests.toString(), Icons.inbox, isAlert: pendingRequests > 0),
              ),
            ],
          ),
        ),
        
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search managed channels...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: context.tokens.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        
        // Channels List
        Expanded(
          child: filteredChannels.isEmpty && _channelService.isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async => _channelService.fetchChannels(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredChannels.length + _ingestingChannels.length,
                  itemBuilder: (context, index) {
                    if (index < _ingestingChannels.length) {
                      final name = _ingestingChannels.elementAt(index);
                      return _buildIngestingCard(name);
                    }
                    final ch = filteredChannels[index - _ingestingChannels.length];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ChannelDetailScreen(channelId: ch.id)),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.tokens.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.tokens.surfaceBorder),
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
                                    Text(ch.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${Formatters.formatSubscribers(ch.subscriberCount)} subs • ${ch.videoCount} videos',
                                      style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                padding: EdgeInsets.zero,
                                onSelected: (val) {
                                  if (val == 'delete') _confirmDeleteChannel(context, ch.id, ch.name);
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 20),
                                        const SizedBox(width: 8),
                                        Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, {bool isAlert = false}) {
    final color = isAlert ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAlert ? color.withValues(alpha: 0.3) : context.tokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12)),
              Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: isAlert ? color : context.tokens.onSurface)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIngestingCard(String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 3, color: Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ingesting $name...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Fetching videos from YouTube', style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsTab(List<Map<String, dynamic>> requests) {
    if (_channelService.isLoadingRequests && requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: context.tokens.onSurfaceDisabled),
              const SizedBox(height: 16),
              const Text('No channel requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('When users request new channels, they will appear here.', textAlign: TextAlign.center, style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _channelService.fetchRequests(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final req = requests[index];
          final id = req['id'] ?? '';
          final status = req['status'] ?? 'PENDING';

          if (status != 'PENDING') {
            return _buildRequestCard(req, false);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: Key(id),
              background: Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                child: Icon(Icons.check, color: Theme.of(context).colorScheme.onPrimary),
              ),
              secondaryBackground: Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(Icons.close, color: Theme.of(context).colorScheme.onError),
              ),
              onDismissed: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  // Approve
                  await _channelService.approveRequest(id, _authService.currentUser?.email);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Channel approved and ingested!')));
                  }
                } else {
                  // Reject
                  await _channelService.rejectRequest(id, 'Rejected by admin');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request rejected.')));
                  }
                }
              },
              child: _buildRequestCard(req, true),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req, bool isPending) {
    final channelUrl = req['channelUrl'] ?? '';
    final notes = req['notes'] ?? '';
    final submittedBy = req['submittedBy'] ?? 'Anonymous';
    final status = req['status'] ?? 'PENDING';

    Color statusColor = context.tokens.accent;
    if (status == 'APPROVED') statusColor = Theme.of(context).colorScheme.primary;
    if (status == 'REJECTED') statusColor = Theme.of(context).colorScheme.error;

    return Container(
      margin: isPending ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tokens.surfaceBorder),
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
          Text('URL: $channelUrl', style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Requested by: $submittedBy', style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13)),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.swipe_right, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text('Swipe right to approve', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                const Spacer(),
                Text('Swipe left to reject', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                const SizedBox(width: 4),
                Icon(Icons.swipe_left, size: 16, color: Theme.of(context).colorScheme.error),
              ],
            )
          ]
        ],
      ),
    );
  }
}
