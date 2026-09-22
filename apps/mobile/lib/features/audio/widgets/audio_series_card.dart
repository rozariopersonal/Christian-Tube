import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_series.dart';

/// Compact cover card for a sermon series, used inside the carousel and the
/// category grid. Tapping invokes [onTap].
///
/// Design: cover art fills a square with an overlaid gradient scrim for the
/// title text, a spring-tap scale animation, and an active-track badge.
class AudioSeriesCard extends StatefulWidget {
  final AudioSeries series;
  final VoidCallback onTap;

  const AudioSeriesCard({
    super.key,
    required this.series,
    required this.onTap,
  });

  @override
  State<AudioSeriesCard> createState() => _AudioSeriesCardState();
}

class _AudioSeriesCardState extends State<AudioSeriesCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _scaleCtrl.reverse();

  void _onTapUp(_) {
    _scaleCtrl.forward();
    widget.onTap();
  }

  void _onTapCancel() => _scaleCtrl.forward();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: AudioPlayerController.instance,
      builder: (context, _) {
        final currentSeriesId =
            AudioPlayerController.instance.state.currentTrack?.seriesId;
        final isActive = currentSeriesId != null &&
            currentSeriesId == widget.series.id;

        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: AnimatedBuilder(
            animation: _scaleCtrl,
            builder: (context, child) =>
                Transform.scale(scale: _scaleCtrl.value, child: child),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  // Cover art (square)
                  AspectRatio(
                    aspectRatio: 1,
                    child: _CoverBackground(
                      coverUrl: widget.series.coverUrl,
                      tokens: tokens,
                      theme: theme,
                    ),
                  ),

                  // Bottom gradient scrim
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.4, 1.0],
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.80),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Active equalizer badge (top-right)
                  if (isActive)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.equalizer_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // Title + track count overlaid at bottom
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.series.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.3,
                            shadows: const [
                              Shadow(blurRadius: 6, color: Colors.black54),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.series.trackCount} tracks',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoverBackground extends StatelessWidget {
  final String? coverUrl;
  final AppTokens tokens;
  final ThemeData theme;

  const _CoverBackground({
    required this.coverUrl,
    required this.tokens,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: coverUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _Fallback(tokens: tokens, theme: theme),
      );
    }
    return _Fallback(tokens: tokens, theme: theme);
  }
}

class _Fallback extends StatelessWidget {
  final AppTokens tokens;
  final ThemeData theme;

  const _Fallback({required this.tokens, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.surfaceVariant,
            theme.colorScheme.primary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.headphones_rounded,
          size: 38,
          color: theme.colorScheme.primary.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
