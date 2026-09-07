import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/playback_state.dart';

/// Adaptive bottom sheet listing the current playback queue, letting the user
/// jump to (or pause) any queued track.
Future<void> showPlaybackQueueSheet(
  BuildContext context,
  AudioPlayerState state,
) {
  final tokens = Theme.of(context).extension<AppTokens>();
  final theme = Theme.of(context);

  return showAdaptiveBottomSheet(
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
                    color: tokens?.surfaceBorder.withValues(alpha: 0.4) ??
                        theme.dividerColor,
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