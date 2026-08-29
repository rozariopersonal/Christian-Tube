import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/config/app_config.dart';
import '../../core/models/video.dart';
import '../../core/utils/formatters.dart';
import '../profile/user_service.dart';
import '../watch/video_player_screen.dart';

class HistoryScreen extends StatefulWidget {
  final List<Video>? history;

  const HistoryScreen({super.key, this.history});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmClearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: tokens.surface,
          title: Text('Clear Watch History?', style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold)),
          content: Text(
            'This will clear your watch history from all ChristianApp sessions on this device.',
            style: TextStyle(color: tokens.onSurfaceMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: tokens.onSurfaceMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Clear History', style: TextStyle(color: scheme.onError)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _userService.clearHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Watch history cleared'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _userService,
      builder: (context, _) {
        final tokens = context.tokens;
        final allHistory = _userService.history;
        final filteredList = _searchQuery.isEmpty
            ? allHistory
            : allHistory.where((v) {
                final q = _searchQuery.toLowerCase();
                return v.title.toLowerCase().contains(q) ||
                    v.channelTitle.toLowerCase().contains(q);
              }).toList();

        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.surface,
            elevation: 0,
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: tokens.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Search in history...',
                      hintStyle: TextStyle(color: tokens.onSurfaceDisabled),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                  )
                : const Text('Watch History', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (!_isSearching && allHistory.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search history',
                  onPressed: () {
                    setState(() {
                      _isSearching = true;
                    });
                  },
                )
              else if (_isSearching)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                ),
              if (allHistory.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_sweep_outlined, color: Theme.of(context).colorScheme.error),
                  tooltip: 'Clear history',
                  onPressed: _confirmClearHistory,
                ),
            ],
          ),
          body: allHistory.isEmpty
              ? _buildEmptyState()
              : filteredList.isEmpty
                  ? Center(
                      child: Text(
                        'No videos matching "$_searchQuery"',
                        style: TextStyle(color: tokens.onSurfaceMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filteredList.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) {
                        final video = filteredList[index];
                        return _buildHistoryRow(context, video);
                      },
                    ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 56,
                color: tokens.onSurfaceDisabled,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Watch History Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Videos and sermons you watch on ChristianApp will automatically appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: tokens.onSurfaceMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow(BuildContext context, Video video) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => VideoPlayerScreen(
              videoId: video.id,
              initialVideo: video,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with duration badge
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    width: 120,
                    height: 68,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 120,
                      height: 68,
                      color: context.tokens.surfaceVariant,
                      child: Icon(Icons.play_circle_outline, color: context.tokens.onSurfaceDisabled),
                    ),
                  ),
                  if (video.duration != null && video.duration!.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.duration!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: context.tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.tokens.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Formatters.formatViews(video.viewCount)} views • ${Formatters.formatTimeAgo(video.publishedAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.tokens.onSurfaceDisabled,
                    ),
                  ),
                ],
              ),
            ),

            // 3-dots Menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: context.tokens.onSurfaceMuted),
              onSelected: (action) async {
                if (action == 'remove') {
                  await _userService.removeFromHistory(video.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed from watch history: ${video.title}'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else if (action == 'share') {
                  Share.share('${AppConfig.apiBaseUrl}/watch/${video.id}');
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      const Text('Remove from history'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Share video'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
