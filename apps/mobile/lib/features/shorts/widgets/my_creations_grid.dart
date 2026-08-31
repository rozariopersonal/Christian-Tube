import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/local_short_item.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';

class MyCreationsGrid extends StatelessWidget {
  final List<LocalShortItem> items;
  final Future<void> Function() onRefresh;
  final Function(int index) onShortTap;
  final Function(LocalShortItem item) onDeleteTap;

  const MyCreationsGrid({
    super.key,
    required this.items,
    required this.onRefresh,
    required this.onShortTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: context.accent,
      backgroundColor: context.tokens.surface,
      onRefresh: onRefresh,
      child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 75, 16, 14),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${items.length} ${items.length == 1 ? 'Creation' : 'Creations'}',
                        style: TextStyle(
                          color: context.tokens.onSurfaceMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onRefresh,
                        icon: Icon(Icons.sync, size: 16, color: context.accent),
                        label: Text(
                          'Refresh',
                          style: TextStyle(color: context.accent, fontSize: 13, fontWeight: FontWeight.bold),
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
                      final item = items[index];
                      return CreationGridCard(
                        item: item,
                        index: index,
                        onTap: () => onShortTap(index),
                        onDeleteTap: () => onDeleteTap(item),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        );
  }
}

class CreationGridCard extends StatelessWidget {
  final LocalShortItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDeleteTap;

  const CreationGridCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    final durSec = (item.clipEndTime - item.clipStartTime).toInt();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDeleteTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.tokens.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.status == ShortCreationStatus.published
                ? context.tokens.surfaceBorder
                : item.statusColor.withValues(alpha: 0.75),
            width: item.status == ShortCreationStatus.published ? 1.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            if (item.sourceVideoThumbnail != null && item.sourceVideoThumbnail!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.sourceVideoThumbnail!,
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

            // Subtle Gradient Overlay
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

            // Top Status Badge Chip
            Positioned(
              top: 8,
              left: 8,
              child: CreationGridBadge(item: item),
            ),

            // Duration Badge & Delete Icon Top-Right
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      Formatters.formatDuration(Duration(seconds: durSec > 0 ? durSec : 60)),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDeleteTap,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline, size: 14, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),

            // Play Icon in Center
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 38,
              ),
            ),

            // Bottom Title & Sermon Source
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sourceVideoTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                  // Progress Bar for actively processing items
                  if (item.status == ShortCreationStatus.downloading ||
                      item.status == ShortCreationStatus.trimming ||
                      item.status == ShortCreationStatus.uploading) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.progress > 0 ? item.progress : null,
                        minHeight: 3,
                        backgroundColor: context.tokens.onSurfaceDisabled,
                        color: item.statusColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreationGridBadge extends StatelessWidget {
  final LocalShortItem item;

  const CreationGridBadge({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.statusColor;
    final isProgressing = item.status == ShortCreationStatus.downloading ||
        item.status == ShortCreationStatus.trimming ||
        item.status == ShortCreationStatus.uploading ||
        item.status == ShortCreationStatus.processing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: context.tokens.background.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isProgressing)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                value: (item.progress > 0 && item.status == ShortCreationStatus.uploading)
                    ? item.progress
                    : null,
                color: color,
              ),
            )
          else
            Icon(
              item.statusIcon,
              size: 11,
              color: color,
            ),
          const SizedBox(width: 5),
          Text(
            item.statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class CreationStatusChip extends StatelessWidget {
  final LocalShortItem item;
  final VoidCallback onRetry;

  const CreationStatusChip({super.key, required this.item, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final color = item.statusColor;
    final isProgressing = item.status == ShortCreationStatus.downloading ||
        item.status == ShortCreationStatus.trimming ||
        item.status == ShortCreationStatus.uploading ||
        item.status == ShortCreationStatus.processing;
    final isActionable = item.status == ShortCreationStatus.failed ||
        item.status == ShortCreationStatus.scheduledUpload;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: context.tokens.background.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
          const BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isProgressing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: (item.progress > 0 && item.status == ShortCreationStatus.uploading)
                    ? item.progress
                    : null,
                color: color,
              ),
            )
          else
            Icon(
              item.statusIcon,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 8),
          Text(
            item.statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isActionable) ...[
            const SizedBox(width: 6),
            const Text('•', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Retry',
                style: TextStyle(
                  color: context.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NonPlayableShortCard extends StatelessWidget {
  final LocalShortItem item;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const NonPlayableShortCard({
    super.key,
    required this.item,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.statusColor;
    final isFailed = item.status == ShortCreationStatus.failed;
    final isScheduled = item.status == ShortCreationStatus.scheduledUpload;
    final isProgressing = item.status == ShortCreationStatus.downloading ||
        item.status == ShortCreationStatus.trimming ||
        item.status == ShortCreationStatus.uploading ||
        item.status == ShortCreationStatus.processing;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background thumbnail with blur
        if (item.sourceVideoThumbnail != null && item.sourceVideoThumbnail!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: item.sourceVideoThumbnail!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: context.tokens.background),
            errorWidget: (_, __, ___) => Container(color: context.tokens.background),
          )
        else
          Container(color: context.tokens.background),

        // Dark frosted overlay
        Container(
          color: context.tokens.scrim.withValues(alpha: 0.78),
        ),

        // Central Status Card
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.tokens.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withValues(alpha: 0.75),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status Icon / Progress Spinner
                  if (isProgressing)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: (item.progress > 0 && item.status == ShortCreationStatus.uploading)
                                ? item.progress
                                : null,
                            strokeWidth: 3.5,
                            color: color,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        Text(
                          '${(item.progress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.statusIcon,
                        size: 44,
                        color: color,
                      ),
                    ),

                  const SizedBox(height: 18),

                  // Title
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Status Message
                  Text(
                    item.statusDisplay,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isFailed ? Colors.redAccent : Colors.white70,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),

                  if (isFailed && item.errorMessage != null && item.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.tokens.surfaceElevated.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.errorMessage!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.tokens.onSurfaceMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Action Buttons (Retry / Re-render / Back)
                  if (isFailed || isScheduled)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.accent,
                            foregroundColor: context.tokens.scrim,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            onRetry();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text(
                            'Retry Now',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.tokens.onSurfaceMuted,
                            side: BorderSide(color: context.tokens.surfaceBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: onClose,
                          child: const Text('Back to Grid', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    )
                  else
                    const Text(
                      '✂️ You can return to the grid or continue watching while this processes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
