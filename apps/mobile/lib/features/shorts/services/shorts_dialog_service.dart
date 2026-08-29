import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/short.dart';
import '../../../core/models/local_short_item.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/ui/channel_avatar.dart';
import 'shorts_orchestrator_service.dart';

class ShortsDialogService {
  static void confirmDeleteCreation(
    BuildContext context,
    LocalShortItem item,
    ShortsOrchestratorService orchestrator,
  ) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.tokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text('Delete Creation', style: TextStyle(color: ctx.tokens.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${item.title}"? This cannot be undone.',
          style: TextStyle(color: ctx.tokens.onSurfaceMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: ctx.tokens.onSurfaceMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              orchestrator.deleteShort(item.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed "${item.title}"'),
                    backgroundColor: context.tokens.surface,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: ctx.tokens.onSurface, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static void shareShort(BuildContext context, Short short, {LocalShortItem? localItem}) {
    HapticFeedback.lightImpact();

    if (localItem != null && localItem.status != ShortCreationStatus.published) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.tokens.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                Icon(Icons.info_outline, color: context.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✂️ This Short is currently ${localItem.statusDisplay.toLowerCase()} and will be shareable once published!',
                    style: TextStyle(color: context.tokens.onSurface, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    final appUrl = 'https://christiantube.app/#/watch/${short.sourceVideoId ?? short.id}?start=${(short.clipStartTime ?? 0).toInt()}';
    final ytUrl = 'https://www.youtube.com/shorts/${short.id}';

    Share.share(
      '🎬 "${short.title}"\n\n'
      '📱 Open in ${AppConfig.appName}:\n$appUrl\n\n'
      '▶️ Watch on YouTube:\n$ytUrl',
      subject: 'Watch "${short.title}" on ${AppConfig.appName}',
    );
  }

  static void showShortDetailsSheet(BuildContext context, Short short, VoidCallback onStopAllPlatformShorts) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.tokens.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ChannelAvatar(
                    avatarUrl: short.channelAvatarUrl,
                    channelTitle: short.channelTitle,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          short.channelTitle,
                          style: TextStyle(
                            color: ctx.tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (short.creatorName != null && short.creatorName!.isNotEmpty)
                          Text(
                            '✂️ Clipped by ${short.creatorName}',
                            style: TextStyle(color: ctx.tokens.onSurfaceMuted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: ctx.tokens.onSurfaceMuted, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                short.title,
                style: TextStyle(
                  color: ctx.tokens.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (short.description != null && short.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Text(
                      short.description!.trim(),
                      style: TextStyle(color: ctx.tokens.onSurfaceMuted, fontSize: 12, height: 1.4),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ctx.tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '👁️ ${short.viewCount > 0 ? Formatters.formatViews(short.viewCount) : '0'} views',
                      style: TextStyle(color: ctx.tokens.onSurfaceMuted, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (short.durationSeconds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ctx.tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '⏱️ ${Formatters.formatDuration(Duration(seconds: short.durationSeconds))}',
                        style: TextStyle(color: ctx.tokens.onSurfaceMuted, fontSize: 11),
                      ),
                    ),
                ],
              ),
              if (short.sourceVideoId != null && short.sourceVideoId!.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ctx.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      onStopAllPlatformShorts();
                      context.push(
                        '/watch/${short.sourceVideoId}?start=${(short.clipStartTime ?? 0).toInt()}',
                      );
                    },
                    icon: const Icon(Icons.play_circle_fill, size: 18),
                    label: const Text(
                      'Watch Full Sermon Video',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
