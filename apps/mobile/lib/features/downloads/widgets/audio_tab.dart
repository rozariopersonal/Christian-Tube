import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/downloads_controller.dart';
import '../models/downloads_state.dart';
import 'common/download_bundle_card.dart';
import 'common/download_item_tile.dart';

class AudioTab extends StatelessWidget {
  final DownloadsController controller;

  const AudioTab({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final itemExtent = (104.0 * textScale.clamp(1.0, 2.2)).toDouble();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final audioSeries = state.audioSeries;
        final storage = state.storage;
        final isWide = ScreenClass.of(context).isMediumOrExpanded;

        return MaxWidthBox(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Audio Storage Overview Card (Zero-overflow responsive card)
                    DownloadBundleCard(
                      icon: Icons.headphones_rounded,
                      title: 'Offline Audio Sermons',
                      subtitle:
                          '${storage.audioTracksCount} tracks across ${storage.audioSeriesCount} series (${storage.audioFormatted})',
                      description:
                          'Downloaded audio sermons play instantly without buffering and are stored in app documents storage.',
                      actionWidget: storage.audioTracksCount > 0
                          ? OutlinedButton.icon(
                              onPressed: () => _confirmClearAllAudio(context),
                              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                              label: const Text('Clear All Audio'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 20),

                    // Section Title
                    Text(
                      'DOWNLOADED SERIES (${audioSeries.length})',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),

              if (audioSeries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.headphones_outlined,
                            size: 56,
                            color: tokens.onSurfaceMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Audio Downloads Yet',
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You can download tracks or full sermon series from the Audio screen to listen offline anywhere.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: GridExtents.bibleManager,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: itemExtent,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildAudioSeriesItem(context, audioSeries[index], tokens),
                      childCount: audioSeries.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildAudioSeriesItem(context, audioSeries[index], tokens),
                      ),
                      childCount: audioSeries.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClearAllAudio(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Downloaded Audio?'),
        content: const Text(
          'All downloaded sermon audio files will be deleted from your device. You can stream or re-download them anytime.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete All')),
        ],
      ),
    );
    if (confirm == true) {
      await controller.clearAllAudio();
    }
  }

  Widget _buildAudioSeriesItem(BuildContext context, AudioDownloadedSeriesItem item, AppTokens tokens) {
    return DownloadItemTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.audio_file_rounded, color: tokens.accent, size: 20),
      ),
      title: item.title,
      subtitle: '${item.trackCount} tracks • ${item.sizeFormatted}',
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
        tooltip: 'Delete Series Audio',
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Remove ${item.title}?'),
              content: Text(
                'All ${item.trackCount} downloaded audio tracks in this series will be removed from your device.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
              ],
            ),
          );
          if (confirm == true) {
            await controller.deleteAudioSeries(item.seriesId);
          }
        },
      ),
    );
  }
}
