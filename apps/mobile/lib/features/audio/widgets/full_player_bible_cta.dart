import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_track.dart';

/// CTA card linking the full player to the corresponding scripture chapter in
/// the Bible Reader when the current sermon references one.
class FullPlayerBibleCta extends StatelessWidget {
  final AudioTrack track;

  const FullPlayerBibleCta({
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

    return Material(
      color: tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).pop();
          context.go(
            '/bible?chapter=${track.scriptureChapter}',
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(
                Icons.menu_book,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Read ${track.scriptureRefText} in Bible Reader',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: tokens.onSurfaceMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}