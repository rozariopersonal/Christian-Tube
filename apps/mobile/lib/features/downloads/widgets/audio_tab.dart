import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/downloads_controller.dart';
import '../models/downloads_state.dart';

class AudioTab extends StatelessWidget {
  final DownloadsController controller;

  const AudioTab({
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
                    // Audio Storage Overview Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tokens.surface, tokens.surfaceElevated],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
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
                                child: Icon(Icons.headphones_rounded, color: tokens.accent, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Offline Audio Sermons',
                                      style: TextStyle(
                                        color: tokens.onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${storage.audioTracksCount} tracks across ${storage.audioSeriesCount} series (${storage.audioFormatted})',
                                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (storage.audioTracksCount > 0)
                                TextButton.icon(
                                  onPressed: () async {
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
                                  },
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                                  label: const Text('Clear All'),
                                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Downloaded audio sermons play instantly without buffering and are stored in app documents storage.',
                            style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section Title
                    Row(
                      children: [
                        Text(
                          'DOWNLOADED SERIES (${audioSeries.length})',
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
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
                          Icon(Icons.headphones_outlined, size: 56, color: tokens.onSurfaceMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text(
                            'No Audio Downloads Yet',
                            style: TextStyle(color: tokens.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You can download tracks or full sermon series from the Audio screen to listen offline anywhere.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13, height: 1.4),
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
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: GridExtents.bibleManager,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 95,
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

  Widget _buildAudioSeriesItem(BuildContext context, AudioDownloadedSeriesItem item, AppTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.audio_file_rounded, color: tokens.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.trackCount} tracks • ${item.sizeFormatted}',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
            tooltip: 'Delete Series Audio',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Remove ${item.title}?'),
                  content: Text('All ${item.trackCount} downloaded audio tracks in this series will be removed from your device.'),
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
        ],
      ),
    );
  }
}
