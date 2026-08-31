import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/short.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';

class CommunityShortsGrid extends StatelessWidget {
  final List<Short> allShorts;
  final List<Short> filteredShorts;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final bool isLoadingMore;
  final Function(int index) onShortTap;
  final String currentFilter;
  final Function(String filterKey) onFilterSelected;

  const CommunityShortsGrid({
    super.key,
    required this.allShorts,
    required this.filteredShorts,
    required this.scrollController,
    required this.onRefresh,
    required this.isLoadingMore,
    required this.onShortTap,
    required this.currentFilter,
    required this.onFilterSelected,
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
                            '${allShorts.length} Shorts',
                            style: TextStyle(
                              color: context.tokens.onSurfaceMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: onRefresh,
                            icon: Icon(Icons.refresh, size: 16, color: context.accent),
                            label: Text(
                              'Refresh',
                              style: TextStyle(color: context.accent, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Quick Filter Chips Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            CommunityFilterChip(
                              label: 'All Shorts',
                              filterKey: 'all',
                              icon: Icons.auto_awesome,
                              currentFilter: currentFilter,
                              onSelected: onFilterSelected,
                            ),
                            const SizedBox(width: 8),
                            CommunityFilterChip(
                              label: '🔥 Popular',
                              filterKey: 'popular',
                              icon: Icons.local_fire_department_rounded,
                              currentFilter: currentFilter,
                              onSelected: onFilterSelected,
                            ),
                            const SizedBox(width: 8),
                            CommunityFilterChip(
                              label: '✨ Recent',
                              filterKey: 'recent',
                              icon: Icons.schedule_rounded,
                              currentFilter: currentFilter,
                              onSelected: onFilterSelected,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
                          final realIndex = allShorts.indexWhere((s) => s.id == short.id);
                          onShortTap(realIndex != -1 ? realIndex : index);
                        },
                      );
                    },
                    childCount: filteredShorts.length,
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

class CommunityFilterChip extends StatelessWidget {
  final String label;
  final String filterKey;
  final IconData icon;
  final String currentFilter;
  final Function(String filterKey) onSelected;

  const CommunityFilterChip({
    super.key,
    required this.label,
    required this.filterKey,
    required this.icon,
    required this.currentFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentFilter == filterKey;
    final onAccent = context.accent.computeLuminance() > 0.45
        ? context.tokens.scrim
        : context.tokens.onSurface;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelected(filterKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.accent : context.tokens.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? context.accent : context.tokens.surfaceBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? onAccent : context.tokens.onSurfaceMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? onAccent : context.tokens.onSurface,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.tokens.surfaceBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
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
                placeholder: (_, __) => Container(color: context.tokens.background),
                errorWidget: (_, __, ___) => Container(
                  color: context.tokens.background,
                  child: Center(child: Icon(Icons.movie, color: context.tokens.onSurfaceDisabled, size: 36)),
                ),
              )
            else
              Container(
                color: context.tokens.background,
                child: Center(child: Icon(Icons.movie, color: context.tokens.onSurfaceDisabled, size: 36)),
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
                  border: Border.all(color: context.tokens.surfaceBorder, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.remove_red_eye, size: 10, color: context.accent),
                    const SizedBox(width: 4),
                    Text(
                      short.viewCount > 0 ? Formatters.formatViews(short.viewCount) : 'Short',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Formatters.formatDuration(Duration(seconds: durSec)),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // 5. Play Icon in Center
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (short.channelAvatarUrl != null && short.channelAvatarUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: short.channelAvatarUrl!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(Icons.person, size: 16, color: Colors.white70),
                          ),
                        )
                      else
                        const Icon(Icons.account_circle, size: 16, color: Colors.white70),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          short.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
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
