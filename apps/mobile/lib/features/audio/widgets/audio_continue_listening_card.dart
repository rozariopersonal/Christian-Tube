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
        final percent = (progress * 100).round();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.surfaceBorder, width: 0.8),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 54,
                    height: 54,
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: tokens.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(isPlaying
                          ? 'Pause'
                          : (percent > 0 ? '$percent%' : 'Resume')),
                    ],
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