import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/models/channel_request.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/ui/channel_avatar.dart';
import '../channel_detail_screen.dart';
import '../channel_service.dart';
import '../widgets/request_channel_sheet.dart';

class UserSubscriptionsScreen extends StatefulWidget {
  final ChannelService? channelService;
  const UserSubscriptionsScreen({super.key, this.channelService});

  @override
  State<UserSubscriptionsScreen> createState() => _UserSubscriptionsScreenState();
}

class _UserSubscriptionsScreenState extends State<UserSubscriptionsScreen> {
  late final ChannelService _channelService = widget.channelService ?? ChannelService();
  final ScrollController _scrollController = ScrollController();
  
  bool _isFabVisible = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _channelService.loadSubscriptions();
    _channelService.fetchChannels();
    
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isFabVisible) setState(() => _isFabVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isFabVisible) setState(() => _isFabVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showRequestChannelDialog(BuildContext context) {
    showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RequestChannelBottomSheet(
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
                backgroundColor: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
        channelService: _channelService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _channelService,
      builder: (context, _) {
        final allChannels = _channelService.channels;
        final subscribedChannels = allChannels.where((c) => c.isSubscribed).toList();
        final recommendedChannels = allChannels.where((c) => !c.isSubscribed).take(10).toList();
        
        final filteredSubscriptions = subscribedChannels.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

        return Scaffold(
          appBar: AppBar(
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Subscriptions',
                maxLines: 1,
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ),
          body: _channelService.isLoading && allChannels.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async => _channelService.fetchChannels(),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // Search Bar
                      if (subscribedChannels.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Search subscriptions...',
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
                        ),
                      
                      // Recommended Carousel
                      if (recommendedChannels.isNotEmpty && _searchQuery.isEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              'Recommended Channels',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 120,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemCount: recommendedChannels.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final ch = recommendedChannels[index];
                                return InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChannelDetailScreen(channelId: ch.id),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 220,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.tokens.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: context.tokens.surfaceBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        ChannelAvatar(
                                          avatarUrl: ch.avatarUrl,
                                          channelTitle: ch.name,
                                          radius: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ch.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${Formatters.formatSubscribers(ch.subscriberCount)} subs',
                                                style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      ],

                      // Subscriptions List
                      if (filteredSubscriptions.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.tv_off_outlined, size: 64, color: context.tokens.onSurfaceDisabled),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isNotEmpty ? 'No matches found' : 'No subscriptions yet',
                                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_searchQuery.isEmpty)
                                    Text(
                                      'Subscribe to channels or submit a channel request.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final ch = filteredSubscriptions[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChannelDetailScreen(channelId: ch.id),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
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
                                            avatarUrl: ch.avatarUrl,
                                            channelTitle: ch.name,
                                            radius: 30,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ch.name,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${Formatters.formatSubscribers(ch.subscriberCount)} subscribers • ${ch.videoCount} videos',
                                                  style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.notifications_active, color: context.tokens.onSurface),
                                            onPressed: () => _channelService.toggleSubscribe(ch.id),
                                            tooltip: 'Unsubscribe',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: filteredSubscriptions.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
          floatingActionButton: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset: _isFabVisible ? Offset.zero : const Offset(0, 2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isFabVisible ? 1 : 0,
              child: FloatingActionButton.extended(
                onPressed: () => _showRequestChannelDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Request Channel'),
              ),
            ),
          ),
        );
      },
    );
  }
}
