import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../controllers/downloads_controller.dart';

/// Pinned banner displayed across all Downloads tabs when any download is in flight.
///
/// Features a real-time progress bar, count of downloading items, and a quick-tap
/// action to navigate directly to the respective tab.
class GlobalDownloadsBanner extends StatelessWidget {
  final DownloadsController controller;
  final Function(int tabIndex)? onNavigateToTab;

  const GlobalDownloadsBanner({
    super.key,
    required this.controller,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDownloading = controller.isAnyDownloading;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: isDownloading
          ? Container(
              key: const ValueKey('active_banner'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.accent.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: tokens.scrim.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final targetTab = controller.firstActiveCategoryTabIndex;
                    onNavigateToTab?.call(targetTab);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: controller.overallDownloadProgress > 0
                                    ? controller.overallDownloadProgress
                                    : null,
                                color: tokens.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        controller.activeDownloadsSummary,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.onSurface,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${(controller.overallDownloadProgress * 100).toInt()}%',
                                      style: TextStyle(
                                        color: tokens.accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${controller.activeDownloadsCount} active • Tap to view tab',
                                  style: TextStyle(
                                    color: tokens.onSurfaceMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: tokens.onSurfaceMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: controller.overallDownloadProgress > 0
                              ? controller.overallDownloadProgress
                              : null,
                          backgroundColor: tokens.surfaceVariant,
                          color: tokens.accent,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('empty_banner')),
    );
  }
}
