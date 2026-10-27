import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Standard, responsive item tile used across Downloads tabs
/// (Bibles, Dictionaries, Books, and Audio series).
///
/// Designed to be completely immune to horizontal RenderFlex overflows on
/// compact screens (320dp) and high system font scaling factors.
class DownloadItemTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? description;
  final String? badgeText;
  final bool isBadgeAccent;
  final Widget trailing;
  final VoidCallback? onInfo;
  final VoidCallback? onTap;
  final bool isDownloading;
  final double? downloadProgress;
  final bool isIndeterminate;

  const DownloadItemTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.description,
    this.badgeText,
    this.isBadgeAccent = true,
    required this.trailing,
    this.onInfo,
    this.onTap,
    this.isDownloading = false,
    this.downloadProgress,
    this.isIndeterminate = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + Badge inside Wrap prevents RenderFlex overflow
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              if (badgeText != null && badgeText!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isBadgeAccent
                                        ? tokens.accent.withValues(alpha: 0.15)
                                        : tokens.surfaceVariant,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    badgeText!,
                                    style: TextStyle(
                                      color: isBadgeAccent
                                          ? tokens.accent
                                          : tokens.onSurfaceMuted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                          if (description != null && description!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onInfo != null)
                          IconButton(
                            icon: Icon(
                              Icons.info_outline,
                              color: tokens.onSurfaceMuted,
                              size: 18,
                            ),
                            tooltip: 'Details & License',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: onInfo,
                          ),
                        trailing,
                      ],
                    ),
                  ],
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isIndeterminate
                          ? null
                          : (downloadProgress != null && downloadProgress! > 0
                              ? downloadProgress
                              : null),
                      backgroundColor: tokens.surfaceVariant,
                      color: tokens.accent,
                      minHeight: 3.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
