import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';

/// Full-screen modal audio player adhering to Material 3 and the design mockup.
class FullAudioPlayerSheet extends StatelessWidget {
  const FullAudioPlayerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FullAudioPlayerSheet(),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return ListenableBuilder(
      listenable: AudioPlayerController.instance,
      builder: (context, _) {
        final state = AudioPlayerController.instance.state;
        final track = state.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final position = state.position;
        final duration = state.duration;
        final progress = state.progress;

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.94,
          decoration: BoxDecoration(
            color: tokens.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                      color: tokens.onSurface,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        track.seriesTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      color: tokens.onSurface,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      // Album Cover Card
                      AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: tokens.surfaceVariant,
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.scrim.withValues(alpha: 0.3),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: track.coverUrl != null &&
                                    track.coverUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: track.coverUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _buildCoverFallback(theme),
                                  )
                                : _buildCoverFallback(theme),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Track Title & Speaker
                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${track.speaker} • ${track.seriesTitle}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Scrubber Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: theme.colorScheme.primary,
                          inactiveTrackColor: tokens.surfaceVariant,
                          thumbColor: theme.colorScheme.primary,
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (val) {
                            final targetMs = (val * duration.inMilliseconds).toInt();
                            AudioPlayerController.instance
                                .seek(Duration(milliseconds: targetMs));
                          },
                        ),
                      ),

                      // Timestamps
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.onSurfaceMuted,
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.onSurfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Playback Controls Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Speed Chip
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => AudioPlayerController.instance
                                .cyclePlaybackSpeed(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceVariant,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${state.speed.toStringAsFixed(1)}x',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tokens.onSurface,
                                ),
                              ),
                            ),
                          ),

                          // 10s Rewind
                          IconButton(
                            icon: const Icon(Icons.replay_10, size: 32),
                            color: tokens.onSurface,
                            onPressed: () => AudioPlayerController.instance
                                .seekRelative(-10),
                          ),

                          // Play/Pause
                          if (state.isLoading)
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: Center(
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            )
                          else
                            InkWell(
                              borderRadius: BorderRadius.circular(36),
                              onTap: () => AudioPlayerController.instance
                                  .togglePlayPause(),
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  state.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  size: 36,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),

                          // 30s Forward
                          IconButton(
                            icon: const Icon(Icons.forward_30, size: 32),
                            color: tokens.onSurface,
                            onPressed: () => AudioPlayerController.instance
                                .seekRelative(30),
                          ),

                          // Sleep Timer
                          IconButton(
                            icon: Icon(
                              Icons.bedtime_outlined,
                              size: 24,
                              color: state.sleepTimerRemainingSeconds != null
                                  ? theme.colorScheme.primary
                                  : tokens.onSurfaceMuted,
                            ),
                            onPressed: () => _showSleepTimerDialog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Bible Synchronizer CTA Card
                      if (track.hasScripture) ...[
                        Material(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.of(context).pop();
                              context.go(
                                '/bible?chapter=${track.scriptureChapter}',
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.menu_book,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Read ${track.scriptureRefText} in Bible Reader',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: tokens.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: tokens.onSurfaceMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoverFallback(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.headphones,
        size: 80,
        color: theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
    );
  }

  void _showSleepTimerDialog(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>();
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: tokens?.background ?? theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sleep Timer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: tokens?.onSurface,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Off', style: TextStyle(color: tokens?.onSurface)),
                  onTap: () {
                    AudioPlayerController.instance.setSleepTimer(null);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: Text('15 minutes', style: TextStyle(color: tokens?.onSurface)),
                  onTap: () {
                    AudioPlayerController.instance.setSleepTimer(15);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: Text('30 minutes', style: TextStyle(color: tokens?.onSurface)),
                  onTap: () {
                    AudioPlayerController.instance.setSleepTimer(30);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: Text('45 minutes', style: TextStyle(color: tokens?.onSurface)),
                  onTap: () {
                    AudioPlayerController.instance.setSleepTimer(45);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: Text('60 minutes', style: TextStyle(color: tokens?.onSurface)),
                  onTap: () {
                    AudioPlayerController.instance.setSleepTimer(60);
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
