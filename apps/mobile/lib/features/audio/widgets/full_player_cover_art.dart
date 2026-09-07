import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_track.dart';

/// Album cover art in the full player, capped at 320dp with a headphones
/// fallback when no cover is available.
class FullPlayerCoverArt extends StatelessWidget {
  final AudioTrack track;

  const FullPlayerCoverArt({
    super.key,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320, maxWidth: 320),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surfaceVariant,
              boxShadow: [
                BoxShadow(
                  color: tokens.scrim.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.coverUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _CoverFallback(),
                  )
                : const _CoverFallback(),
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Icon(
        Icons.headphones,
        size: 80,
        color: theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
    );
  }
}