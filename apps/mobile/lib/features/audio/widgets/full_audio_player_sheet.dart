import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/playback_state.dart';

/// Full-screen adaptive modal audio player adhering to Material 3,
/// the design mockup, and repository adaptive standards (capping width at 640dp on wide viewports).
class FullAudioPlayerSheet extends StatefulWidget {
  const FullAudioPlayerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FullAudioPlayerSheet(),
    );
  }

  @override
  State<FullAudioPlayerSheet> createState() => _FullAudioPlayerSheetState();
}

class _FullAudioPlayerSheetState extends State<FullAudioPlayerSheet> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

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

        final duration = state.duration;
        final currentProgress = _isDragging ? _dragProgress : state.progress;
        final displayPosition = _isDragging
            ? Duration(milliseconds: (_dragProgress * duration.inMilliseconds).toInt())
            : state.position;

        final hasPrevious = state.queueIndex > 0 || state.position.inSeconds > 5;
        final hasNext = state.queueIndex >= 0 && state.queueIndex < state.queue.length - 1;

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
                      tooltip: 'Minimize Player',
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
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: tokens.onSurface),
                      tooltip: 'More options',
                      color: tokens.surfaceElevated,
                      onSelected: (value) {
                        switch (value) {
                          case 'share':
                            Share.share(
                              'Listening to "${track.title}" by ${track.speaker} on Christian Tube\n${track.audioUrl}',
                            );
                            break;
                          case 'sleep_timer':
                            _showSleepTimerDialog(context);
                            break;
                          case 'view_series':
                            Navigator.of(context).pop();
                            context.push('/audio/series/${track.seriesId}');
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 20, color: tokens.onSurface),
                              const SizedBox(width: 12),
                              Text('Share Sermon', style: TextStyle(color: tokens.onSurface)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'sleep_timer',
                          child: Row(
                            children: [
                              Icon(Icons.bedtime_outlined, size: 20, color: tokens.onSurface),
                              const SizedBox(width: 12),
                              Text('Sleep Timer', style: TextStyle(color: tokens.onSurface)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'view_series',
                          child: Row(
                            children: [
                              Icon(Icons.folder_open_outlined, size: 20, color: tokens.onSurface),
                              const SizedBox(width: 12),
                              Text('View Series', style: TextStyle(color: tokens.onSurface)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // Error Banner if stream error occurred
                      if (state.status == AudioPlaybackStatus.error) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: theme.colorScheme.onErrorContainer,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  state.errorMessage ?? 'Unable to stream audio.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: () {
                                  AudioPlayerController.instance.playTrack(
                                    track,
                                    queue: state.queue,
                                    resumePositionSec: state.position.inSeconds,
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Retry', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Album Cover Card
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 320),
                        child: AspectRatio(
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
                              child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: track.coverUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => _buildCoverFallback(theme),
                                    )
                                  : _buildCoverFallback(theme),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

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
                      const SizedBox(height: 18),

                      // Smooth Scrubber Slider (Stateful drag)
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
                          value: currentProgress,
                          onChanged: (val) {
                            setState(() {
                              _isDragging = true;
                              _dragProgress = val;
                            });
                          },
                          onChangeEnd: (val) {
                            final targetMs = (val * duration.inMilliseconds).toInt();
                            AudioPlayerController.instance
                                .seek(Duration(milliseconds: targetMs));
                            setState(() {
                              _isDragging = false;
                            });
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
                              _formatDuration(displayPosition),
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
                      const SizedBox(height: 14),

                      // Main Playback Controls Row (Prev, Rewind 10, Play/Pause, Forward 30, Next)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Previous Track
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: const Icon(Icons.skip_previous, size: 28),
                            color: hasPrevious
                                ? tokens.onSurface
                                : tokens.onSurfaceDisabled.withValues(alpha: 0.35),
                            tooltip: 'Previous Track',
                            onPressed: hasPrevious
                                ? () => AudioPlayerController.instance.skipPrevious()
                                : null,
                          ),

                          // 10s Rewind
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: const Icon(Icons.replay_10, size: 28),
                            color: tokens.onSurface,
                            tooltip: 'Rewind 10s',
                            onPressed: () => AudioPlayerController.instance.seekRelative(-10),
                          ),

                          // Play/Pause
                          if (state.isLoading)
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            )
                          else
                            InkWell(
                              borderRadius: BorderRadius.circular(32),
                              onTap: () => AudioPlayerController.instance.togglePlayPause(),
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 34,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),

                          // 30s Forward
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: const Icon(Icons.forward_30, size: 28),
                            color: tokens.onSurface,
                            tooltip: 'Forward 30s',
                            onPressed: () => AudioPlayerController.instance.seekRelative(30),
                          ),

                          // Next Track
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: const Icon(Icons.skip_next, size: 28),
                            color: hasNext
                                ? tokens.onSurface
                                : tokens.onSurfaceDisabled.withValues(alpha: 0.35),
                            tooltip: 'Next Track',
                            onPressed: hasNext
                                ? () => AudioPlayerController.instance.skipNext()
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Secondary Utilities Row (Speed, Sleep Timer, Queue) wrapped to prevent overflow
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          // Speed Chip
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => AudioPlayerController.instance.cyclePlaybackSpeed(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

                          // Sleep Timer Chip
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _showSleepTimerDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: state.sleepTimerRemainingSeconds != null
                                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                                    : tokens.surfaceVariant,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bedtime_outlined,
                                    size: 15,
                                    color: state.sleepTimerRemainingSeconds != null
                                        ? theme.colorScheme.primary
                                        : tokens.onSurfaceMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    state.sleepTimerRemainingSeconds != null
                                        ? '${(state.sleepTimerRemainingSeconds! / 60).ceil()}m'
                                        : 'Sleep Timer',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: state.sleepTimerRemainingSeconds != null
                                          ? theme.colorScheme.primary
                                          : tokens.onSurfaceMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Queue / Up Next Chip
                          if (state.queue.isNotEmpty)
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _showQueueSheet(context, state),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceVariant,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.queue_music,
                                      size: 16,
                                      color: tokens.onSurfaceMuted,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Queue (${state.queue.length})',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: tokens.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                      style: theme.textTheme.bodyMedium?.copyWith(
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

  void _showQueueSheet(BuildContext context, AudioPlayerState state) {
    final tokens = Theme.of(context).extension<AppTokens>();
    final theme = Theme.of(context);

    showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Material(
          color: tokens?.surfaceElevated ?? theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens?.surfaceBorder ?? theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.queue_music, color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Playback Queue (${state.queue.length} Tracks)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: tokens?.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: tokens?.surfaceBorder ?? theme.dividerColor, height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.queue.length,
                  separatorBuilder: (_, __) => Divider(
                    color: tokens?.surfaceBorder.withValues(alpha: 0.4) ?? theme.dividerColor,
                    height: 1,
                    indent: 52,
                  ),
                  itemBuilder: (context, index) {
                    final item = state.queue[index];
                    final isCurrent = item.id == state.currentTrack?.id;

                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(alpha: 0.15)
                              : tokens?.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: isCurrent
                            ? Icon(Icons.equalizer, size: 16, color: theme.colorScheme.primary)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: tokens?.onSurfaceMuted,
                                ),
                              ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? theme.colorScheme.primary : tokens?.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        item.formattedDuration,
                        style: TextStyle(fontSize: 11, color: tokens?.onSurfaceMuted),
                      ),
                      trailing: isCurrent && state.isPlaying
                          ? Icon(Icons.pause_circle_outline, color: theme.colorScheme.primary, size: 22)
                          : Icon(Icons.play_circle_outline, color: tokens?.onSurfaceMuted, size: 22),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (isCurrent) {
                          AudioPlayerController.instance.togglePlayPause();
                        } else {
                          AudioPlayerController.instance.playTrack(item, queue: state.queue);
                        }
                      },
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

  void _showSleepTimerDialog(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>();
    final theme = Theme.of(context);
    showAdaptiveBottomSheet(
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
