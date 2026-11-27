import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/layout/adaptivity.dart';
import '../../core/layout/content_width.dart';
import '../../core/models/channel_request.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/ui/channel_card.dart';
import '../../shared/ui/channel_follow_tile.dart';
import '../auth/auth_service.dart';
import 'channel_detail_screen.dart';
import 'channel_service.dart';
import 'widgets/add_channel_sheet.dart';
import 'widgets/request_channel_sheet.dart';

/// Fixed tile height for the channels grid.
///
/// [ChannelCard] lays out a banner, an overlapping avatar, title, metadata and
/// a footer action, so the extent has to clear the tallest of those at the
/// default text scale. Below ~280 the description is silently clipped.
const double kChannelCardGridExtent = 300;

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen>
    with SingleTickerProviderStateMixin {
  final ChannelService _channelService = ChannelService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  String _searchQuery = '';
  bool _wasAdmin = false;
  final Set<String> _busyRequestIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _wasAdmin = _authService.isAdmin;
    _channelService.loadSubscriptions();
    if (_wasAdmin) {
      _channelService.fetchAdminChannels();
      _channelService.fetchRequests();
    } else {
      _channelService.fetchChannels();
    }
    _authService.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final isAdminNow = _authService.isAdmin;
    if (isAdminNow && !_wasAdmin) {
      _channelService.fetchAdminChannels();
      _channelService.fetchRequests();
    }
    _wasAdmin = isAdminNow;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _authService.isAdmin;

    return AnimatedBuilder(
      animation: _channelService,
      builder: (context, _) {
        final channels = _channelService.channels;
        final requests = _channelService.channelRequests;
        final pendingRequests =
            requests.where((r) => r['status'] == 'PENDING').toList();

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                isAdmin ? 'Channel Administration' : 'Channels',
                maxLines: 1,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            actions: [
              if (isAdmin)
                IconButton(
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: 'Add Channel Directly',
                  onPressed: () => _showAddChannelDialog(context),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.tokens.surfaceVariant,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${channels.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: context.tokens.accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${pendingRequests.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: context.tokens.onSurface,
                                  ),
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
                    _buildChannelsList(channels, isAdmin: true),
                    _buildRequestsList(requests),
                  ],
                )
              : _buildChannelsList(channels, isAdmin: false),
          floatingActionButton: !isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _showRequestChannelDialog(context),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Request Channel'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildChannelsList(List<dynamic> channels, {required bool isAdmin}) {
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
              Icon(
                Icons.tv_off_outlined,
                size: 64,
                color: context.tokens.onSurfaceDisabled,
              ),
              const SizedBox(height: 16),
              Text(
                'No channels added yet',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAdmin
                    ? 'As an Admin, you can search and add channels directly.'
                    : 'Submit a channel request to get it approved by the administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.tokens.onSurfaceMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => isAdmin
                    ? _showAddChannelDialog(context)
                    : _showRequestChannelDialog(context),
                icon: Icon(isAdmin ? Icons.add : Icons.send),
                label: Text(isAdmin ? 'Add Channel' : 'Request Channel'),
              ),
            ],
          ),
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? channels
        : channels.where((c) {
            final name = (c.name ?? '').toString().toLowerCase();
            final desc = (c.description ?? '').toString().toLowerCase();
            return name.contains(query) || desc.contains(query);
          }).toList();

    final screenClass = ScreenClass.of(context);
    final isCompact = screenClass == ScreenClass.compact;

    return RefreshIndicator(
      onRefresh: () async {
        if (isAdmin) {
          await _channelService.fetchAdminChannels();
        } else {
          await _channelService.fetchChannels();
        }
      },
      child: MaxWidthBox(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search channels...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: context.tokens.surfaceVariant,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'No matching channels found',
                              style: TextStyle(
                                color: context.tokens.onSurfaceMuted,
                              ),
                            ),
                            if (_searchQuery.trim().length >= 2) ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => isAdmin
                                    ? _showAddChannelDialog(
                                        context,
                                        initialQuery: _searchQuery.trim(),
                                      )
                                    : _showRequestChannelDialog(
                                        context,
                                        initialQuery: _searchQuery.trim(),
                                      ),
                                icon: Icon(
                                  isAdmin ? Icons.add : Icons.playlist_add,
                                  size: 18,
                                ),
                                label: Text(
                                  isAdmin
                                      ? 'Search "${_searchQuery.trim()}" on YouTube'
                                      : 'Request "${_searchQuery.trim()}" on YouTube',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : (isCompact
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _buildChannelTile(
                              context,
                              filtered[index],
                              isAdmin,
                            );
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 380,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 84,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _buildChannelTile(
                              context,
                              filtered[index],
                              isAdmin,
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelTile(BuildContext context, dynamic ch, bool isAdmin) {
    final bool isActive = ch.isActive as bool? ?? true;
    final adminMenu = isAdmin
        ? PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (val) async {
              if (val == 'toggle_active') {
                final ok = await _channelService.toggleChannelActive(ch);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? (isActive
                                ? 'Channel suspended'
                                : 'Channel activated')
                            : 'Failed to update channel',
                      ),
                    ),
                  );
                }
              } else if (val == 'delete') {
                _confirmDeleteChannel(context, ch.id, ch.name);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'toggle_active',
                child: Row(
                  children: [
                    Icon(
                      isActive
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(isActive ? 'Suspend Channel' : 'Activate Channel'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remove Channel',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          )
        : null;

    return ChannelFollowTile(
      channelId: ch.id,
      title: isActive ? ch.name : '${ch.name} (Suspended)',
      avatarUrl: ch.avatarUrl,
      subscriberCount: ch.subscriberCount,
      videoCount: ch.videoCount,
      isFollowed: ch.isSubscribed,
      trailingMenu: adminMenu,
      onToggleFollow: () => _channelService.toggleFollow(ch.id),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChannelDetailScreen(channelId: ch.id),
          ),
        );
      },
    );
  }

  Widget _buildRequestsList(List<Map<String, dynamic>> requests) {
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
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: context.tokens.onSurfaceDisabled,
              ),
              const SizedBox(height: 16),
              const Text(
                'No channel requests',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'When users request new channels, they will appear here for review.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.tokens.onSurfaceMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _channelService.fetchRequests(),
      child: MaxWidthBox(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final req = requests[index];
            final id = (req['id'] ?? '').toString();
            final channelUrl = (req['channelUrl'] ?? '').toString();
            final channelName = (req['channelName'] ?? '').toString();
            final notes = (req['notes'] ?? '').toString();
            final submittedBy = (req['submittedBy'] ?? 'Anonymous').toString();
            final status = (req['status'] ?? 'PENDING').toString();
            final displayTitle = channelName.isNotEmpty
                ? channelName
                : (notes.isNotEmpty ? notes : channelUrl);
            final isBusy = _busyRequestIds.contains(id);

            Color statusColor = context.tokens.accent;
            if (status == 'APPROVED') {
              statusColor = Theme.of(context).colorScheme.primary;
            }
            if (status == 'REJECTED') {
              statusColor = Theme.of(context).colorScheme.error;
            }

            return Container(
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
                          displayTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'URL: $channelUrl',
                    style: TextStyle(
                      color: context.tokens.onSurfaceMuted,
                      fontSize: 13,
                    ),
                  ),
                  if (notes.isNotEmpty && notes != displayTitle) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Notes: $notes',
                      style: TextStyle(
                        color: context.tokens.onSurfaceMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Requested by: $submittedBy',
                    style: TextStyle(
                      color: context.tokens.onSurfaceMuted,
                      fontSize: 13,
                    ),
                  ),
                  if (status == 'PENDING') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _confirmRejectRequest(context, id),
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.error,
                            size: 18,
                          ),
                          label: Text(
                            'Reject',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                          ),
                          onPressed: isBusy
                              ? null
                              : () => _handleApproveRequest(context, id),
                          icon: isBusy
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: Text(isBusy ? 'Working...' : 'Approve & Ingest'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleApproveRequest(BuildContext context, String id) async {
    setState(() => _busyRequestIds.add(id));
    try {
      final success = await _channelService.approveRequest(
        id,
        _authService.currentUser?.email,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Channel approved & video ingestion started!'
                  : (_channelService.lastRequestError ?? 'Approval failed'),
            ),
            backgroundColor: success
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyRequestIds.remove(id));
      }
    }
  }

  void _showAddChannelDialog(BuildContext context, {String? initialQuery}) {
    showAdaptiveBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AddChannelBottomSheet(
        initialQuery: initialQuery,
        onAddDirect: (url, name) async {
          final success = await _channelService.addChannel(
            channelUrl: url,
            name: name,
            adminEmail: _authService.currentUser?.email,
          );
          return (
            ok: success,
            error: success
                ? null
                : (_channelService.lastRequestError ?? 'Failed to add channel'),
          );
        },
        onSearch: _channelService.searchYouTubeChannels,
        getLastSearchError: () => _channelService.lastSearchError,
      ),
    ).then((added) {
      if (added == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Channel added successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    });
  }

  void _showRequestChannelDialog(BuildContext context, {String? initialQuery}) {
    showAdaptiveBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => RequestChannelBottomSheet(
        initialQuery: initialQuery,
        onSubmitRequest: (url, name) async {
          final req = ChannelRequest(
            channelUrl: url,
            channelName: name,
            language: 'en',
            submittedBy: _authService.currentUser?.email,
            createdAt: DateTime.now(),
          );
          final success = await _channelService.submitChannelRequest(req);
          return (
            ok: success,
            error: success ? null : _channelService.lastRequestError,
          );
        },
        onSearch: _channelService.searchYouTubeChannels,
        getLastSearchError: () => _channelService.lastSearchError,
      ),
    ).then((submitted) {
      if (submitted == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Channel request submitted to admin!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    });
  }

  void _confirmDeleteChannel(
    BuildContext context,
    String channelId,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Channel?'),
        content: Text(
          'Are you sure you want to remove "$name"? All its videos will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
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
          decoration: const InputDecoration(
            hintText: 'Reason for rejection (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              final reason = reasonController.text.trim();
              Navigator.pop(ctx);
              setState(() => _busyRequestIds.add(requestId));
              try {
                final ok = await _channelService.rejectRequest(
                  requestId,
                  reason,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Channel request rejected'
                            : (_channelService.lastRequestError ??
                                'Rejection failed'),
                      ),
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _busyRequestIds.remove(requestId));
                }
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    ).whenComplete(reasonController.dispose);
  }
}
