import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/video.dart';
import '../../core/config/app_config.dart';
import '../../core/layout/content_width.dart';
import '../../core/link/deep_link_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../features/playlists/services/playlist_service.dart';
import '../../features/playlists/services/watch_later_service.dart';
import '../../features/playlists/widgets/save_to_playlist_sheet.dart';

class VideoOptionsBottomSheet extends StatelessWidget {
  final Video video;
  final VoidCallback? onSaveToPlaylist;
  final VoidCallback? onAddToWatchPlan;
  final WatchLaterService? watchLaterService;
  final PlaylistService? playlistService;

  const VideoOptionsBottomSheet({
    super.key,
    required this.video,
    this.onSaveToPlaylist,
    this.onAddToWatchPlan,
    this.watchLaterService,
    this.playlistService,
  });

  static Future<void> show(
    BuildContext context, {
    required Video video,
    VoidCallback? onSaveToPlaylist,
    VoidCallback? onAddToWatchPlan,
    WatchLaterService? watchLaterService,
    PlaylistService? playlistService,
  }) {
    final tokens = context.tokens;
    return showAdaptiveBottomSheet(
      context: context,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => VideoOptionsBottomSheet(
        video: video,
        onSaveToPlaylist: onSaveToPlaylist ??
            () => SaveToPlaylistSheet.show(
                  context,
                  video: video,
                  watchLaterService: watchLaterService,
                  playlistService: playlistService,
                ),
        onAddToWatchPlan: onAddToWatchPlan,
        watchLaterService: watchLaterService,
        playlistService: playlistService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final wl = watchLaterService ?? WatchLaterService.instance;
    final inWatchLater = wl.isWatchLater(video.id);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.onSurfaceDisabled.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                inWatchLater
                    ? Icons.watch_later_rounded
                    : Icons.watch_later_outlined,
                color: inWatchLater ? context.accent : null,
              ),
              title: Text(
                inWatchLater ? 'Remove from Watch Later' : 'Save to Watch Later',
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                final saved = await wl.toggleWatchLater(video);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      saved ? 'Saved to Watch Later' : 'Removed from Watch Later',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Save to Playlist'),
              onTap: () {
                Navigator.pop(context);
                if (onSaveToPlaylist != null) {
                  onSaveToPlaylist!();
                } else {
                  SaveToPlaylistSheet.show(
                    context,
                    video: video,
                    watchLaterService: watchLaterService,
                    playlistService: playlistService,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.alarm_add),
              title: const Text('Add to Daily Watch Plan'),
              onTap: () {
                Navigator.pop(context);
                onAddToWatchPlan?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share Video'),
              onTap: () {
                Navigator.pop(context);
                final shareUrl = DeepLinkService.video(video.id);
                Share.share('Watch "${video.title}" on ${AppConfig.appName}: $shareUrl');
              },
            ),
          ],
        ),
      ),
    );
  }
}
