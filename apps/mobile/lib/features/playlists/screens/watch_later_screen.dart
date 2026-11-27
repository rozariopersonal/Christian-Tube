import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/models/video.dart';
import '../../../core/theme/app_tokens.dart';
import '../services/watch_later_service.dart';

class WatchLaterScreen extends StatelessWidget {
  final WatchLaterService? watchLaterService;

  const WatchLaterScreen({super.key, this.watchLaterService});

  WatchLaterService get _service =>
      watchLaterService ?? WatchLaterService.instance;

  void _openVideo(BuildContext context, List<Video> videos, int index) {
    final video = videos[index];
    context.push(
      '/watch/${video.id}',
      extra: {
        'video': video,
        'playlist': videos,
        'playlistTitle': 'Watch Later',
        'initialIndex': index,
      },
    );
  }

  Future<void> _removeVideo(BuildContext context, Video video) async {
    final messenger = ScaffoldMessenger.of(context);
    await _service.removeFromWatchLater(video.id);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Removed from Watch Later'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final service = _service;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final videos = service.videos;
        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text(
              'Watch Later',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: MaxWidthBox(
            child: videos.isEmpty
                ? _buildEmptyState(context, theme, tokens)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                videos.length == 1
                                    ? '1 video'
                                    : '${videos.length} videos',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: tokens.onSurfaceMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () => _openVideo(context, videos, 0),
                              icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              label: const Text('Play All'),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: tokens.surfaceBorder),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: videos.length,
                          itemBuilder: (context, index) {
                            final video = videos[index];
                            return _WatchLaterRow(
                              video: video,
                              onTap: () => _openVideo(context, videos, index),
                              onRemove: () => _removeVideo(context, video),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    AppTokens tokens,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.watch_later_outlined,
              size: 56,
              color: tokens.onSurfaceMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No videos in Watch Later',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Save videos from the feed, search, or player to watch them anytime.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchLaterRow extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WatchLaterRow({
    required this.video,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: tokens.surfaceVariant,
                          child: Icon(
                            Icons.play_circle_outline,
                            color: tokens.onSurfaceDisabled,
                          ),
                        ),
                      ),
                    ),
                    if (video.duration != null &&
                        video.duration!.isNotEmpty &&
                        video.duration != '0:00')
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.scrim,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            video.duration!,
                            style: TextStyle(
                              color: tokens.onScrim,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 20, color: tokens.onSurfaceMuted),
              tooltip: 'Remove from Watch Later',
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}
