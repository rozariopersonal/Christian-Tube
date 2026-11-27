import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/video.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import 'video_options_bottom_sheet.dart';
import 'video_thumbnail_overlays.dart';

class RecommendationVideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback? onTap;

  const RecommendationVideoCard({
    super.key,
    required this.video,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return InkWell(
      onTap: onTap ?? () => context.push('/watch/${video.id}', extra: video),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: tokens.surfaceVariant,
                          child: Icon(Icons.play_circle_outline, color: tokens.onSurfaceDisabled),
                        ),
                      ),
                    ),
                    if (video.duration != null && video.duration!.isNotEmpty && video.duration != '0:00')
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: tokens.scrim,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            video.duration!,
                            style: TextStyle(color: tokens.onScrim, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    VideoWatchedOverlays(
                      videoId: video.id,
                      duration: video.duration,
                      compact: true,
                      badgeTopOffset: 4,
                      badgeLeftOffset: 4,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${video.channelTitle} • ${Formatters.formatViews(video.viewCount)} views • ${Formatters.formatTimeAgo(video.publishedAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_vert, size: 18, color: tokens.onSurfaceMuted),
              tooltip: 'More options',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
              onPressed: () => VideoOptionsBottomSheet.show(context, video: video),
            ),
          ],
        ),
      ),
    );
  }
}
