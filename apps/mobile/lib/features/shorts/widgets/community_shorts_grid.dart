import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/short.dart';
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 3
                : 2;

        return RefreshIndicator(
          color: const Color(0xFFF59E0B),
          backgroundColor: const Color(0xFF1E293B),
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
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFF59E0B)),
                            label: const Text(
                              'Refresh',
                              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
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
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
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
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        );
      },
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelected(filterKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
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
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
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
                placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF0F172A),
                  child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
                ),
              )
            else
              Container(
                color: const Color(0xFF0F172A),
                child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),
              ),

            // 2. Gradient Overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x77000000),
                    Color(0x00000000),
                    Color(0xDD000000),
                  ],
                  stops: [0.0, 0.4, 1.0],
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
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_red_eye, size: 10, color: Color(0xFFF59E0B)),
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
