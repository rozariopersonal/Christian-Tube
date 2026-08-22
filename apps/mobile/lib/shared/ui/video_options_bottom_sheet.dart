import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/video.dart';
import '../../core/config/app_config.dart';

class VideoOptionsBottomSheet extends StatelessWidget {
  final Video video;
  final VoidCallback? onSaveToPlaylist;
  final VoidCallback? onAddToWatchPlan;

  const VideoOptionsBottomSheet({
    super.key,
    required this.video,
    this.onSaveToPlaylist,
    this.onAddToWatchPlan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Save to Playlist'),
              onTap: () {
                Navigator.pop(context);
                onSaveToPlaylist?.call();
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
                final shareUrl = '${AppConfig.apiBaseUrl}/watch/${video.id}';
                Share.share('Watch "${video.title}" on ${AppConfig.appName}: $shareUrl');
              },
            ),
          ],
        ),
      ),
    );
  }
}
