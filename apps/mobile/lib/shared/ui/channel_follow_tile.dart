import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import 'channel_avatar.dart';

/// Reusable channel list tile with consistent Follow / Following interaction.
///
/// Matches the high-density, rounded card design originally introduced in
/// onboarding:
/// - 12dp rounded surface card with accent-highlighted border when followed.
/// - Channel avatar with initials fallback.
/// - Title and subscriber/video count metadata.
/// - Distinct pill action button (`Follow` vs `Following`) or custom `actionButton`.
/// - Optional `trailingMenu` (e.g. for admin actions) and `badge`.
class ChannelFollowTile extends StatelessWidget {
  final String channelId;
  final String title;
  final String? avatarUrl;
  final int subscriberCount;
  final int videoCount;
  final String? subtitle;
  final bool isFollowed;
  final VoidCallback? onToggleFollow;
  final Widget? actionButton;
  final VoidCallback? onTap;
  final Widget? badge;
  final Widget? trailingMenu;

  const ChannelFollowTile({
    super.key,
    required this.channelId,
    required this.title,
    this.avatarUrl,
    this.subscriberCount = 0,
    this.videoCount = 0,
    this.subtitle,
    this.isFollowed = false,
    this.onToggleFollow,
    this.actionButton,
    this.onTap,
    this.badge,
    this.trailingMenu,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final displaySubtitle = subtitle ??
        '${Formatters.formatSubscribers(subscriberCount)} subscribers • $videoCount videos';

    final effectiveButton = actionButton ??
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isFollowed
                ? context.accent
                : tokens.surfaceVariant,
            foregroundColor: isFollowed
                ? tokens.onScrim
                : tokens.onSurface,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: onToggleFollow,
          child: Text(
            isFollowed ? 'Following' : 'Follow',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

    final cardContent = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFollowed ? context.accent : tokens.surfaceBorder,
          width: isFollowed ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          ChannelAvatar(
            avatarUrl: avatarUrl,
            channelTitle: title,
            radius: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: tokens.onSurface,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 0,
                        child: badge!,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  displaySubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          if (trailingMenu != null) ...[
            const SizedBox(width: 4),
            trailingMenu!,
          ],
          const SizedBox(width: 8),
          effectiveButton,
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
