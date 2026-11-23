import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/channel.dart';
import '../../../core/models/short.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/ui/channel_avatar.dart';
import '../../../shared/ui/video_thumbnail_overlays.dart';

class CommunityShortsGrid extends StatelessWidget {
  final List<Short> allShorts;
  final List<Short> filteredShorts;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final bool isLoadingMore;
  final Function(int index) onShortTap;
  final List<Channel> filterChannels;
  final Set<String> selectedChannelIds;
  final VoidCallback onChannelFilterTap;
  final bool likedOnly;
  final ValueChanged<bool> onLikedOnlyChanged;
  final String watchStatusFilter;
  final ValueChanged<String>? onWatchStatusChanged;

  const CommunityShortsGrid({
    super.key,
    required this.allShorts,
    required this.filteredShorts,
    required this.scrollController,
    required this.onRefresh,
    required this.isLoadingMore,
    required this.onShortTap,
    required this.filterChannels,
    required this.selectedChannelIds,
    required this.onChannelFilterTap,
    required this.likedOnly,
    required this.onLikedOnlyChanged,
    this.watchStatusFilter = 'all',
    this.onWatchStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: context.accent,
      backgroundColor: context.tokens.surface,
      onRefresh: onRefresh,
      child: CustomScrollView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 75, 16, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filteredShorts.length} Shorts',
                        style: TextStyle(
                          color: context.tokens.onSurfaceMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onRefresh,
                        icon: Icon(Icons.refresh,
                            size: 16, color: context.accent),
                        label: Text(
                          'Refresh',
                          style: TextStyle(
                              color: context.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Liked'),
                        avatar: Icon(
                          likedOnly
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 17,
                        ),
                        selected: likedOnly,
                        onSelected: onLikedOnlyChanged,
                      ),
                      OutlinedButton.icon(
                        onPressed: onChannelFilterTap,
                        icon: const Icon(Icons.tune),
                        label: Text(
                          selectedChannelIds.isEmpty
                              ? 'Channels'
                              : 'Channels · ${selectedChannelIds.length}',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.tokens.onSurface,
                          side: BorderSide(color: context.tokens.surfaceBorder),
                          backgroundColor: context.tokens.surface,
                        ),
                      ),
                      if (onWatchStatusChanged != null) ...[
                        FilterChip(
                          label: const Text('Watched'),
                          selected: watchStatusFilter == 'watched',
                          onSelected: (_) => onWatchStatusChanged!('watched'),
                        ),
                        FilterChip(
                          label: const Text('Unwatched'),
                          selected: watchStatusFilter == 'unwatched',
                          onSelected: (_) => onWatchStatusChanged!('unwatched'),
                        ),
                        FilterChip(
                          label: const Text('In Progress'),
                          selected: watchStatusFilter == 'in_progress',
                          onSelected: (_) =>
                              onWatchStatusChanged!('in_progress'),
                        ),
                      ],
                      for (final channel in filterChannels
                          .where((channel) =>
                              selectedChannelIds.contains(channel.id))
                          .take(3))
                        ChannelAvatar(
                          avatarUrl: channel.avatarUrl,
                          channelTitle: channel.name,
                          radius: 12,
                        ),
                      if (selectedChannelIds.length > 3)
                        Text(
                          '+${selectedChannelIds.length - 3}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: context.tokens.onSurfaceMuted,
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (filteredShorts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                child: Center(
                  child: Text(
                    'No Shorts from the selected channels.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.tokens.onSurfaceMuted,
                        ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverConstrainedCrossAxis(
                maxExtent: 1080,
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 150,
                    childAspectRatio: 9 / 16,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final short = filteredShorts[index];
                      return CommunityGridCard(
                        short: short,
                        onTap: () {
                          final realIndex =
                              allShorts.indexWhere((s) => s.id == short.id);
                          onShortTap(realIndex != -1 ? realIndex : index);
                        },
                      );
                    },
                    childCount: filteredShorts.length,
                  ),
                ),
              ),
            ),
          if (isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: context.accent),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class CommunityGridCard extends StatelessWidget {
  final Short short;
  final VoidCallback onTap;

  const CommunityGridCard({
    super.key,
    required this.short,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final durSec = short.durationSeconds > 0
        ? short.durationSeconds
        : Short.parseDurationInSeconds(short.duration);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.tokens.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.tokens.surfaceBorder),
          boxShadow: [
            BoxShadow(
              color: context.tokens.scrim.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Thumbnail
            if (short.thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: short.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: context.tokens.background),
                errorWidget: (_, __, ___) => Container(
                  color: context.tokens.background,
                  child: Center(
                      child: Icon(Icons.movie,
                          color: context.tokens.onSurfaceDisabled, size: 36)),
                ),
              )
            else
              Container(
                color: context.tokens.background,
                child: Center(
                    child: Icon(Icons.movie,
                        color: context.tokens.onSurfaceDisabled, size: 36)),
              ),

            // 2. Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.tokens.scrim.withValues(alpha: 0.47),
                    context.tokens.scrim.withValues(alpha: 0.0),
                    context.tokens.scrim.withValues(alpha: 0.87),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // 3. View Count / Verified Chip Top-Left
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: context.tokens.scrim.withValues(alpha: 0.87),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: context.tokens.surfaceBorder, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.remove_red_eye, size: 10, color: context.accent),
                    const SizedBox(width: 4),
                    Text(
                      short.viewCount > 0
                          ? Formatters.formatViews(short.viewCount)
                          : 'Short',
                      style: TextStyle(
                          color: context.tokens.onScrim,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Duration Badge Top-Right
            if (durSec > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.tokens.scrim,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Formatters.formatDuration(Duration(seconds: durSec)),
                    style: TextStyle(
                        color: context.tokens.onScrim,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // 4.5 Watched Badge & 5dp Progress Bar
            Positioned.fill(
              child: VideoWatchedOverlays(
                videoId: short.id,
                duration: short.duration,
                durationSeconds: durSec > 0 ? durSec : null,
                compact: true,
                badgeTopOffset: 34,
                badgeLeftOffset: 8,
              ),
            ),

            // 5. Play Icon in Center
            Center(
              child: Icon(
                Icons.play_circle_fill,
                color: context.tokens.onScrimMuted,
                size: 38,
              ),
            ),

            // 6. Bottom Title & Channel
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    short.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.tokens.onScrim,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: context.tokens.scrim, blurRadius: 4)
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (short.channelAvatarUrl != null &&
                          short.channelAvatarUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: short.channelAvatarUrl!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(Icons.person,
                                size: 16, color: context.tokens.onScrimMuted),
                          ),
                        )
                      else
                        Icon(Icons.account_circle,
                            size: 16, color: context.tokens.onScrimMuted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          short.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.tokens.onScrimMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
