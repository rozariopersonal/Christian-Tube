import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../features/profile/user_service.dart';

/// Shared thumbnail overlays for Video and Short cards:
/// - Top-left **Watched** badge when the item reached its last 10 seconds.
/// - Bottom 5dp progress bar when playback progress is > 3%.
class VideoWatchedOverlays extends StatelessWidget {
  final String videoId;
  final String? duration;
  final int? durationSeconds;
  final bool compact;
  final double badgeTopOffset;
  final double badgeLeftOffset;

  const VideoWatchedOverlays({
    super.key,
    required this.videoId,
    this.duration,
    this.durationSeconds,
    this.compact = false,
    this.badgeTopOffset = 8.0,
    this.badgeLeftOffset = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final userService = UserService();
    return ListenableBuilder(
      listenable: userService,
      builder: (context, _) {
        final watched = userService.isWatched(
          videoId,
          duration: duration,
          durationSeconds: durationSeconds,
        );
        final progress = userService.progressFraction(
          videoId,
          duration: duration,
          durationSeconds: durationSeconds,
        );
        if (!watched && progress <= 0) {
          return const SizedBox.shrink();
        }

        final tokens = context.tokens;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (watched)
              Positioned(
                top: badgeTopOffset,
                left: badgeLeftOffset,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 5 : 7,
                    vertical: compact ? 2 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.scrim.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(compact ? 4 : 6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: compact ? 11 : 13,
                        color: context.accent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Watched',
                        style: TextStyle(
                          color: tokens.onScrim,
                          fontSize: compact ? 9.5 : 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: tokens.scrim.withValues(alpha: 0.35)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: ColoredBox(color: context.accent),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
