import 'package:cached_network_image/cached_network_image.dart';
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
          subtitleText += ' ΓÇó Resumes at $m:$s';
        }
        if (track.hasScripture) {
          subtitleText += ' ΓÇó ${track.scriptureRefText}';
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

        // Scripture ref becomes a chip tag
        final scriptureChip = track.hasScripture
            ? Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  track.scriptureRefText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null;

        return Material(
          color: isCurrentTrack
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: _TrackLeading(
              track: track,
              index: index,
              isCurrentTrack: isCurrentTrack,
              isPlaying: state.isPlaying,
              theme: theme,
              tokens: tokens,
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // Duration + resume hint (no scripture here ΓÇö moved to chip)
                  () {
                    String s = track.formattedDuration;
                    if (!isCurrentTrack && savedPos > 5) {
                      final m = savedPos ~/ 60;
                      final sec = (savedPos % 60).toString().padLeft(2, '0');
                      s += ' ΓÇó Resumes at $m:$sec';
                    }
                    return s;
                  }(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
                if (scriptureChip != null) scriptureChip,
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AudioTrackDownloadControl(track: track),
                IconButton(
                  icon: Icon(
                    isCurrentTrack && state.isPlaying
                        ? Icons.pause_circle_rounded
                        : Icons.play_circle_rounded,
                    size: 30,
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
          ),
        );
      },
    );
  }
}

/// Leading widget for a track list tile: cover art thumbnail (or number badge
/// / equalizer indicator as fallback).
class _TrackLeading extends StatelessWidget {
  final AudioTrack track;
  final int index;
  final bool isCurrentTrack;
  final bool isPlaying;
  final ThemeData theme;
  final AppTokens tokens;

  const _TrackLeading({
    required this.track,
    required this.index,
    required this.isCurrentTrack,
    required this.isPlaying,
    required this.theme,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover = track.coverUrl != null && track.coverUrl!.isNotEmpty;

    if (hasCover) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _NumberBadge(
                index: index,
                isCurrentTrack: isCurrentTrack,
                isPlaying: isPlaying,
                theme: theme,
                tokens: tokens,
              ),
            ),
          ),
          if (isCurrentTrack)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Icon(
                      isPlaying
                          ? Icons.equalizer_rounded
                          : Icons.pause_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return _NumberBadge(
      index: index,
      isCurrentTrack: isCurrentTrack,
      isPlaying: isPlaying,
      theme: theme,
      tokens: tokens,
    );
  }
}

class _NumberBadge extends StatelessWidget {
  final int index;
  final bool isCurrentTrack;
  final bool isPlaying;
  final ThemeData theme;
  final AppTokens tokens;

  const _NumberBadge({
    required this.index,
    required this.isCurrentTrack,
    required this.isPlaying,
    required this.theme,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCurrentTrack
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : tokens.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: isCurrentTrack && isPlaying
          ? Icon(Icons.equalizer_rounded, size: 18, color: theme.colorScheme.primary)
          : Text(
              '${index + 1}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isCurrentTrack
                    ? theme.colorScheme.primary
                    : tokens.onSurfaceMuted,
              ),
            ),
    );
  }
}
