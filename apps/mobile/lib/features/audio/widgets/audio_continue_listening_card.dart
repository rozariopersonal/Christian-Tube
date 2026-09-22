import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_track.dart';

/// "Continue Listening" card surfaced at the top of the Audio Library with the
/// last played track's progress and a resume button.
class AudioContinueListeningCard extends StatelessWidget {
  final AudioTrack track;
  final int savedSeconds;

  const AudioContinueListeningCard({
    super.key,
    required this.track,
    required this.savedSeconds,
  });

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
        final isCurrent = state.currentTrack?.id == track.id;
        final isPlaying = isCurrent && state.isPlaying;
        final currentSeconds = isCurrent
            ? state.position.inSeconds
            : savedSeconds;
        final progress = track.durationSeconds > 0
            ? (currentSeconds / track.durationSeconds).clamp(0.0, 1.0)
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  tokens.surfaceElevated,
                  tokens.surfaceVariant,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tokens.surfaceBorder, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: tokens.isDark ? 0.3 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                // Cover art with shadow
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: tokens.surfaceVariant,
                      child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: track.coverUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.headphones,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : Icon(
                              Icons.headphones,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue Listening',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tokens.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Gradient progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 6,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: tokens.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Compact circular play/pause button
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () {
                      if (isCurrent) {
                        AudioPlayerController.instance.togglePlayPause();
                      } else {
                        AudioPlayerController.instance.playTrack(
                          track,
                          resumePositionSec: savedSeconds,
                        );
                      }
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
}
