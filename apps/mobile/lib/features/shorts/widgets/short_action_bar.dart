import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/short.dart';
import '../../../core/services/user_sync_service.dart';
import '../../../core/theme/app_tokens.dart';
import 'shorts_chrome.dart';

class ShortActionBar extends StatelessWidget {
  final Short short;
  final VoidCallback onShare;
  final VoidCallback? onNote;
  final bool hasNote;
  final bool enableLike;

  const ShortActionBar({
    super.key,
    required this.short,
    required this.onShare,
    this.onNote,
    this.hasNote = false,
    this.enableLike = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (enableLike) ...[
          _buildLikeButton(context),
          const SizedBox(height: 14),
        ],
        if (onNote != null) ...[
          _buildNoteButton(context),
          const SizedBox(height: 14),
        ],
        _buildShareButton(context),
      ],
    );
  }

  Widget _buildNoteButton(BuildContext context) {
    return GestureDetector(
      onTap: onNote,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasNote
                  ? context.accent.withValues(alpha: 0.22)
                  : context.shortsChromeFill,
              border: Border.all(
                color: hasNote ? context.accent : context.shortsChromeFg,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: context.shortsChromeShadow.withValues(alpha: 0.54),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              hasNote
                  ? Icons.sticky_note_2_rounded
                  : Icons.sticky_note_2_outlined,
              color: hasNote ? context.accent : context.shortsChromeFg,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            hasNote ? 'Note ✓' : 'Note',
            style: TextStyle(
              color: hasNote ? context.accent : context.shortsChromeFg,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              shadows: [
                Shadow(color: context.shortsChromeShadow, blurRadius: 6),
                Shadow(color: context.shortsChromeShadow, blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildLikeButton(BuildContext context) {
    return AnimatedBuilder(
      animation: UserSyncService.instance,
      builder: (context, _) {
        final isLiked = UserSyncService.instance.isLiked(
          UserSyncService.likedShortType,
          short.id,
        );
        return Semantics(
          button: true,
          toggled: isLiked,
          label: isLiked ? 'Liked, tap to remove like' : 'Like',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (UserSyncService.instance.activeUserId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sign in to save liked Shorts'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              UserSyncService.instance.setLiked(
                itemType: UserSyncService.likedShortType,
                itemId: short.id,
                liked: !isLiked,
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: isLiked ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLiked
                            ? context.accent.withValues(alpha: 0.22)
                            : context.shortsChromeFill,
                        border: Border.all(
                          color: isLiked
                              ? context.accent
                              : context.shortsChromeFg,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.shortsChromeShadow
                                .withValues(alpha: 0.54),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color:
                            isLiked ? context.accent : context.shortsChromeFg,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isLiked ? 'Liked' : 'Like',
                    style: TextStyle(
                      color: isLiked ? context.accent : context.shortsChromeFg,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      shadows: [
                        Shadow(
                            color: context.shortsChromeShadow, blurRadius: 6),
                        Shadow(
                            color: context.shortsChromeShadow, blurRadius: 2),
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

  Widget _buildShareButton(BuildContext context) {
    final onAccent = context.accent.computeLuminance() > 0.45
        ? context.shortsChromeFg
        : context.shortsChromeFgMuted;
    return GestureDetector(
      onTap: onShare,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.accent,
              boxShadow: [
                BoxShadow(
                  color: context.accent.withValues(alpha: 0.65),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: context.shortsChromeShadow.withValues(alpha: 0.54),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.shortsChromeFg, width: 1.5),
            ),
            child: Icon(
              Icons.share_rounded,
              color: onAccent,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Share',
            style: TextStyle(
              color: context.shortsChromeFg,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              shadows: [
                Shadow(color: context.shortsChromeShadow, blurRadius: 6),
                Shadow(color: context.shortsChromeShadow, blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
