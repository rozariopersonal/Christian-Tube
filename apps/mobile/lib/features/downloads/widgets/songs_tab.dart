import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/downloads_controller.dart';

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
              // 1. Songs Database Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tokens.surface, tokens.surfaceElevated],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.music_note_rounded, color: tokens.accent, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Offline Songbook & Hymns',
                                style: TextStyle(
                                  color: tokens.onSurface,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Full-Text Search (FTS5) Database • ~8.2 MB',
                                style: TextStyle(
                                  color: tokens.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Installs the precompiled Christian Tube songbook catalog locally. Unlocks instant title and lyric search, songbook transliterations, and offline chords/lyrics access even in airplane mode.',
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 18),
                    Divider(color: tokens.surfaceBorder, height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              Text(
                                isInstalled
                                    ? 'Installed (${storage.songsFormatted})'
                                    : 'Not Downloaded',
                                style: TextStyle(
                                  color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (isInstalled)
                          OutlinedButton.icon(
                            onPressed: () async {
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
                            },
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Remove'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tokens.onSurfaceMuted,
                            ),
                          )
                        else if (isDownloading)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text(
                              progress > 0
                                  ? '${(progress * 100).toInt()}%'
                                  : 'Downloading…',
                              style: TextStyle(
                                color: tokens.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: controller.downloadSongs,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download Songs (~8.2 MB)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor: tokens.background,
                            ),
                          ),
                      ],
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          backgroundColor: tokens.surfaceVariant,
                          color: tokens.accent,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Info Cards
              _buildFeatureTile(
                icon: Icons.search_rounded,
                title: 'Instant FTS5 Search',
                subtitle: 'Searches through thousands of hymn and song lyrics in milliseconds with full tokenization.',
                tokens: tokens,
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                icon: Icons.translate_rounded,
                title: 'Multilingual Collections',
                subtitle: 'Includes English, Tamil, and Malayalam song collections with phonetic transliterations.',
                tokens: tokens,
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                icon: Icons.airplanemode_active_rounded,
                title: 'Zero Latency Offline Access',
                subtitle: 'Practice, sing, or lead worship without dependency on cellular or church Wi-Fi networks.',
                tokens: tokens,
              ),
            ],
          ),
        );
      },
    );
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
