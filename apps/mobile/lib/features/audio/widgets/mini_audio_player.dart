import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/playback_state.dart';
import 'full_audio_player_sheet.dart';

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

    return Align(
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              // Thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  color: tokens.surfaceVariant,
                                  child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: track.coverUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.headphones,
                                            color: theme.colorScheme.primary,
                                            size: 24,
                                          ),
                                        )
                                      : Icon(
                                          Icons.headphones,
                                          color: theme.colorScheme.primary,
                                          size: 24,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),

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
                                    const SizedBox(height: 2),
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
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
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
                                    size: 34,
                                    color: theme.colorScheme.primary,
                                  ),
                                  tooltip: state.isPlaying ? 'Pause' : 'Play',
                                  onPressed: () =>
                                      AudioPlayerController.instance.togglePlayPause(),
                                ),

                              // Dismiss button
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 20,
                                  color: tokens.onSurfaceMuted,
                                ),
                                tooltip: 'Dismiss mini player',
                                onPressed: () =>
                                    AudioPlayerController.instance.dismissMiniPlayer(),
                              ),
                            ],
                          ),
                        ),

                        // Hairline Progress Bar
                        LinearProgressIndicator(
                          value: state.progress,
                          minHeight: 2.5,
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
    );
  }
}
