import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_track.dart';
import 'audio_track_download_control.dart';

/// One row in the series track list: number/equalizer badge, title, resume and
/// scripture hints, per-track download control, and a play/pause affordance.
class AudioTrackListTile extends StatelessWidget {
  final AudioTrack track;
  final int index;
  final int savedPositionSeconds;
  final List<AudioTrack> queue;

  const AudioTrackListTile({
    super.key,
    required this.track,
    required this.index,
    required this.savedPositionSeconds,
    required this.queue,
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
        final isCurrentTrack = state.currentTrack?.id == track.id;
        final savedPos = savedPositionSeconds;

        String subtitleText = track.formattedDuration;
        if (!isCurrentTrack && savedPos > 5) {
          final m = savedPos ~/ 60;
          final s = (savedPos % 60).toString().padLeft(2, '0');
          subtitleText += ' • Resumes at $m:$s';
        }
        if (track.hasScripture) {
          subtitleText += ' • ${track.scriptureRefText}';
        }

        void playFromHere() {
          if (isCurrentTrack) {
            AudioPlayerController.instance.togglePlayPause();
          } else {
            AudioPlayerController.instance.playTrack(
              track,
              queue: queue,
              resumePositionSec: savedPos > 5 ? savedPos : null,
            );
          }
        }

        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrentTrack
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : tokens.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: isCurrentTrack && state.isPlaying
                ? Icon(
                    Icons.equalizer,
                    size: 18,
                    color: theme.colorScheme.primary,
                  )
                : Text(
                    '${index + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isCurrentTrack
                          ? theme.colorScheme.primary
                          : tokens.onSurfaceMuted,
                    ),
                  ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.normal,
              color: isCurrentTrack
                  ? theme.colorScheme.primary
                  : tokens.onSurface,
            ),
          ),
          subtitle: Text(
            subtitleText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AudioTrackDownloadControl(track: track),
              IconButton(
                icon: Icon(
                  isCurrentTrack && state.isPlaying
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  color: isCurrentTrack
                      ? theme.colorScheme.primary
                      : tokens.onSurfaceMuted,
                ),
                tooltip: isCurrentTrack && state.isPlaying ? 'Pause' : 'Play',
                onPressed: playFromHere,
              ),
            ],
          ),
          onTap: playFromHere,
        );
      },
    );
  }
}