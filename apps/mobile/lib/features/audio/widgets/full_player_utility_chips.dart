import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/playback_state.dart';

/// Secondary utility row (speed chip, sleep timer chip, queue chip), wrapped so
/// it never overflows at narrow widths.
class FullPlayerUtilityChips extends StatelessWidget {
  final AudioPlayerState state;
  final VoidCallback onSleepTimer;
  final VoidCallback onQueue;

  const FullPlayerUtilityChips({
    super.key,
    required this.state,
    required this.onSleepTimer,
    required this.onQueue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return Wrap(
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
          onTap: onSleepTimer,
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
            onTap: onQueue,
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
    );
  }
}