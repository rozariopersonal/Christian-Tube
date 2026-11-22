import 'package:flutter/material.dart';
import '../../../core/models/short.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/services/user_sync_service.dart';
import 'shorts_chrome.dart';

class ShortActionBar extends StatelessWidget {
  final Short short;
  final VoidCallback onShare;
  final bool enableLike;

  const ShortActionBar({
    super.key,
    required this.short,
    required this.onShare,
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
        _buildShareButton(context),
      ],
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
        return GestureDetector(
          onTap: () => UserSyncService.instance.setLiked(
            itemType: UserSyncService.likedShortType,
            itemId: short.id,
            liked: !isLiked,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.shortsChromeFill,
                  border: Border.all(color: context.shortsChromeFg, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: context.shortsChromeShadow.withValues(alpha: 0.54),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  color: isLiked ? context.accent : context.shortsChromeFg,
                  size: 24,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isLiked ? 'Liked' : 'Like',
                style: TextStyle(
                  color: context.shortsChromeFg,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  shadows: [
                    Shadow(color: context.shortsChromeShadow, blurRadius: 6),
                    Shadow(color: context.shortsChromeShadow, blurRadius: 2),
                  ],
                ),
              ),
            ],
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
              gradient: LinearGradient(
                colors: [
                  context.accent,
                  context.accent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
              fontSize: 12,
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
