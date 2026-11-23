import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_tokens.dart';
import '../../audio/models/audio_track.dart';

/// Action pill row rendered below the video player & channel header.
class VideoActionBar extends StatelessWidget {
  final bool isLiked;
  final VoidCallback onToggleLike;
  final AudioTrack? matchedAudioTrack;
  final VoidCallback? onListenAudio;
  final VoidCallback onClip;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onOpenYouTube;

  const VideoActionBar({
    super.key,
    required this.isLiked,
    required this.onToggleLike,
    this.matchedAudioTrack,
    this.onListenAudio,
    required this.onClip,
    required this.onShare,
    required this.onSave,
    required this.onOpenYouTube,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (matchedAudioTrack != null && onListenAudio != null) ...[
          _ActionPill(
            icon: Icons.headphones,
            label: 'Listen to Audio',
            onTap: onListenAudio!,
          ),
          const SizedBox(width: 8),
        ],
        _HeartLikePill(
          isLiked: isLiked,
          onTap: onToggleLike,
        ),
        const SizedBox(width: 8),
        _ActionPill(
          icon: Icons.content_cut,
          label: 'Clip',
          onTap: onClip,
        ),
        const SizedBox(width: 8),
        _ActionPill(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: onShare,
        ),
        const SizedBox(width: 8),
        _ActionPill(
          icon: Icons.bookmark_add_outlined,
          label: 'Save',
          onTap: onSave,
        ),
        const SizedBox(width: 8),
        _ActionPill(
          icon: Icons.open_in_new,
          label: 'YouTube',
          onTap: onOpenYouTube,
        ),
      ],
    );
  }
}

class _HeartLikePill extends StatelessWidget {
  final bool isLiked;
  final VoidCallback onTap;

  const _HeartLikePill({
    required this.isLiked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isLiked ? context.accent : tokens.onSurface,
        );

    return Semantics(
      button: true,
      toggled: isLiked,
      label: isLiked ? 'Liked, tap to remove like' : 'Like',
      child: Tooltip(
        message: isLiked ? 'Liked' : 'Like',
        child: Material(
          color: isLiked
              ? context.accent.withValues(alpha: 0.14)
              : tokens.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: isLiked
                ? BorderSide(color: context.accent.withValues(alpha: 0.5))
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: isLiked ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color: isLiked ? context.accent : tokens.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLiked ? 'Liked' : 'Like',
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tokens.onSurface,
        );

    return Material(
      color: tokens.surfaceVariant,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: tokens.onSurface),
                const SizedBox(width: 6),
                Text(label, style: labelStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
