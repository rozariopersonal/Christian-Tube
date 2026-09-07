import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/playback_state.dart';

/// Main playback transport row: previous, rewind 10s, play/pause, forward 30s,
/// next. Dispatches directly to [AudioPlayerController.instance].
class FullPlayerControls extends StatelessWidget {
  final AudioPlayerState state;
  final bool hasPrevious;
  final bool hasNext;

  const FullPlayerControls({
    super.key,
    required this.state,
    required this.hasPrevious,
    required this.hasNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
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
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.replay_10, size: 28),
          color: tokens.onSurface,
          tooltip: 'Rewind 10s',
          onPressed: () => AudioPlayerController.instance.seekRelative(-10),
        ),
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
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.forward_30, size: 28),
          color: tokens.onSurface,
          tooltip: 'Forward 30s',
          onPressed: () => AudioPlayerController.instance.seekRelative(30),
        ),
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
    );
  }
}