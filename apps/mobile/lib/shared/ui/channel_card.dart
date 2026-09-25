import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/formatters.dart';
import 'channel_avatar.dart';

class ChannelCard extends StatelessWidget {
  final String title;
  final String? description;
  final String avatarUrl;
  final String? bannerUrl;
  final int subscriberCount;
  final int videoCount;
  final String? language;
  final VoidCallback? onTap;
  final Widget actionButton;
  final Widget? trailingMenu;
  final bool isCompact;

  const ChannelCard({
    super.key,
    required this.title,
    this.description,
    required this.avatarUrl,
    this.bannerUrl,
    this.subscriberCount = 0,
    this.videoCount = 0,
    this.language,
    this.onTap,
    required this.actionButton,
    this.trailingMenu,
    this.isCompact = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.tokens.surfaceBorder),
      ),
      color: context.tokens.surface,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner & Avatar Stack
            SizedBox(
              height: 80,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Banner
                  Positioned.fill(
                    child: bannerUrl != null && bannerUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: bannerUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: context.tokens.surfaceVariant,
                          ),
                  ),
                  // Scrim for better contrast
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Avatar
                  Positioned(
                    left: 16,
                    bottom: -20,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: context.tokens.surface, width: 3),
                      ),
                      child: ChannelAvatar(
                        avatarUrl: avatarUrl,
                        channelTitle: title,
                        radius: 24,
                      ),
                    ),
                  ),
                  // Trailing Menu
                  if (trailingMenu != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.tokens.surface.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: trailingMenu!,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24), // Space for avatar overlap
            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${Formatters.formatSubscribers(subscriberCount)} subs',
                          style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                        ),
                        Text(
                          '•',
                          style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                        ),
                        Text(
                          '$videoCount videos',
                          style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                        ),
                        if (language != null && language!.isNotEmpty) ...[
                          Text(
                            '•',
                            style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.tokens.surfaceVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              language!.toUpperCase(),
                              style: TextStyle(color: context.tokens.onSurface, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description!,
                        maxLines: isCompact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Footer Action
            Padding(
              padding: const EdgeInsets.all(16),
              child: isCompact
                  ? SizedBox(width: double.infinity, child: actionButton)
                  : Align(
                      alignment: Alignment.centerRight,
                      child: actionButton,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
