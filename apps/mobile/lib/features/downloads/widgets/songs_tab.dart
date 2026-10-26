import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/downloads_controller.dart';
import 'common/download_bundle_card.dart';

class SongsTab extends StatelessWidget {
  final DownloadsController controller;

  const SongsTab({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final isInstalled = state.songsInstalled;
        final isDownloading = state.isSongsDownloading;
        final progress = state.songsProgress;
        final storage = state.storage;

        return MaxWidthBox(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Songs Database Hero Card
              DownloadBundleCard(
                icon: Icons.music_note_rounded,
                title: 'Offline Songbook & Hymns',
                subtitle: 'Full-Text Search (FTS5) Database • ~8.2 MB',
                description:
                    'Installs the precompiled Christian Tube songbook catalog locally. Unlocks instant title and lyric search, songbook transliterations, and offline chords/lyrics access even in airplane mode.',
                isDownloading: isDownloading,
                progress: progress,
                progressLabel: progress > 0
                    ? 'Downloading Songs: ${(progress * 100).toInt()}%'
                    : 'Downloading Songs…',
                statusWidget: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isInstalled
                        ? tokens.accent.withValues(alpha: 0.15)
                        : tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInstalled ? Icons.check_circle : Icons.cloud_outlined,
                        size: 14,
                        color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isInstalled
                              ? 'Installed (${storage.songsFormatted})'
                              : 'Not Downloaded',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actionWidget: isInstalled
                    ? OutlinedButton.icon(
                        onPressed: () => _confirmDeleteSongs(context),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Remove'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.onSurfaceMuted,
                        ),
                      )
                    : FilledButton(
                        onPressed: controller.downloadSongs,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.background,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download_rounded, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Download Songs (~8.2 MB)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 16),

              // 2. Feature Info Tiles
              _buildFeatureTile(
                icon: Icons.search_rounded,
                title: 'Instant FTS5 Search',
                subtitle:
                    'Searches through thousands of hymn and song lyrics in milliseconds with full tokenization.',
                tokens: tokens,
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                icon: Icons.translate_rounded,
                title: 'Multilingual Collections',
                subtitle:
                    'Includes English, Tamil, and Malayalam song collections with phonetic transliterations.',
                tokens: tokens,
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                icon: Icons.airplanemode_active_rounded,
                title: 'Zero Latency Offline Access',
                subtitle:
                    'Practice, sing, or lead worship without dependency on cellular or church Wi-Fi networks.',
                tokens: tokens,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSongs(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Offline Songs?'),
        content: const Text(
          'The offline songbook package will be removed from your device. The app will return to live streaming.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await controller.deleteSongs();
    }
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required AppTokens tokens,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: tokens.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
