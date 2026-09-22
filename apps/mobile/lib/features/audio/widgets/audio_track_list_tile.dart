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

        Widget buildFallbackBox() {
          return Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${index + 1}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurfaceMuted,
              ),
            ),
          );
        }

        return ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              children: [
                if (track.thumbnailUrl != null || track.coverUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      track.thumbnailUrl ?? track.coverUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => buildFallbackBox(),
                    ),
                  )
                else
                  buildFallbackBox(),
                if (isCurrentTrack)
                  Container(
                    decoration: BoxDecoration(
                      color: tokens.scrim.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(track.thumbnailUrl != null || track.coverUrl != null ? 4 : 8),
                    ),
                    alignment: Alignment.center,
                    child: state.isPlaying
                        ? Icon(
                            Icons.equalizer,
                            size: 24,
                            color: theme.colorScheme.primary,
                          )
                        : Icon(
                            Icons.pause,
                            size: 24,
                            color: theme.colorScheme.primary,
                          ),
                  ),
              ],
            ),
          ),
          title: Text(
            track.title,
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