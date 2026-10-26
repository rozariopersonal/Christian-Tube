import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/playback_state.dart';
import 'full_audio_player_sheet.dart';

/// Standard height reserved for the floating mini audio player.
const double kMiniAudioPlayerHeight = 72.0;

/// Persistent floating mini-player docked right above the bottom navigation bar.
///
/// Supports tap to expand full player, horizontal swipe for previous/next track,
/// vertical swipe up to open sheet, and adaptive max-width constraint on tablets/desktop.
class MiniAudioPlayer extends StatelessWidget {
  final AudioPlayerState state;

  const MiniAudioPlayer({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return SizedBox(
      height: kMiniAudioPlayerHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Semantics(
              label: 'Now playing: ${track.title} by ${track.speaker}',
              button: true,
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
                    FullAudioPlayerSheet.show(context);
                  } else if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
                    if (state.isPlaying) {
                      AudioPlayerController.instance.togglePlayPause();
                    }
                    AudioPlayerController.instance.dismissMiniPlayer();
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -300) {
                      // Swipe Left -> Next Track
                      AudioPlayerController.instance.skipNext();
                    } else if (details.primaryVelocity! > 300) {
                      // Swipe Right -> Previous Track
                      AudioPlayerController.instance.skipPrevious();
                    }
                  }
                },
                child: Material(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 4,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => FullAudioPlayerSheet.show(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle hint
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 30,
                            height: 3,
                            decoration: BoxDecoration(
                              color: tokens.onSurfaceMuted.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          child: Row(
                            children: [
                              // Thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  color: tokens.surfaceVariant,
                                  child: track.displayImageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: track.displayImageUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.headphones,
                                            color: theme.colorScheme.primary,
                                            size: 22,
                                          ),
                                        )
                                      : Icon(
                                          Icons.headphones,
                                          color: theme.colorScheme.primary,
                                          size: 22,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Title & Speaker
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: tokens.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '${track.speaker} • ${track.seriesTitle}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: tokens.onSurfaceMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Play/Pause button
                              if (state.isLoading)
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                IconButton(
                                  icon: Icon(
                                    state.isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_filled,
                                    size: 32,
                                    color: theme.colorScheme.primary,
                                  ),
                                  tooltip: state.isPlaying ? 'Pause' : 'Play',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  onPressed: () =>
                                      AudioPlayerController.instance.togglePlayPause(),
                                ),

                              // Close button
                              IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: tokens.onSurfaceMuted,
                                ),
                                tooltip: 'Close player',
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () {
                                  if (state.isPlaying) {
                                    AudioPlayerController.instance.togglePlayPause();
                                  }
                                  AudioPlayerController.instance.dismissMiniPlayer();
                                },
                              ),
                            ],
                          ),
                        ),

                        // Hairline Progress Bar
                        LinearProgressIndicator(
                          value: state.progress,
                          minHeight: 2.0,
                          backgroundColor: tokens.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
