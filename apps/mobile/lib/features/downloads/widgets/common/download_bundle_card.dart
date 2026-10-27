import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Reusable hero card used for storage readiness, bundles, and database status
/// across Downloads tabs (Overview, Books, Songs, Audio).
///
/// Guaranteed to prevent RenderFlex overflow via responsive wrapping of actions
/// and status pills.
class DownloadBundleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String description;
  final Widget? statusWidget;
  final Widget? actionWidget;
  final Widget? secondaryAction;
  final bool isDownloading;
  final double? progress;
  final String? progressLabel;
  final Widget? customContent;
  final bool isGradient;
  final VoidCallback? onHeaderAction;
  final Widget? headerAction;

  const DownloadBundleCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.description,
    this.statusWidget,
    this.actionWidget,
    this.secondaryAction,
    this.isDownloading = false,
    this.progress,
    this.progressLabel,
    this.customContent,
    this.isGradient = true,
    this.onHeaderAction,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isGradient ? null : tokens.surfaceVariant,
        gradient: isGradient
            ? LinearGradient(
                colors: [tokens.surface, tokens.surfaceElevated],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon Avatar + Title / Subtitle + Optional Header Action
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tokens.accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (headerAction != null) headerAction!,
            ],
          ),
          const SizedBox(height: 12),

          // Body Description
          Text(
            description,
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),

          if (customContent != null) ...[
            const SizedBox(height: 14),
            customContent!,
          ],

          // Progress Indicator
          if (isDownloading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (progress != null && progress! > 0) ? progress : null,
                backgroundColor: tokens.surfaceVariant,
                color: tokens.accent,
                minHeight: 5,
              ),
            ),
            if (progressLabel != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  progressLabel!,
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],

          // Action / Status Bar (Uses Wrap to prevent overflow)
          if (!isDownloading && (statusWidget != null || actionWidget != null || secondaryAction != null)) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, barConstraints) {
                final maxBarWidth = barConstraints.maxWidth;
                return Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (statusWidget != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxBarWidth),
                        child: statusWidget!,
                      ),
                    if (actionWidget != null || secondaryAction != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxBarWidth),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (secondaryAction != null) secondaryAction!,
                            if (actionWidget != null) actionWidget!,
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
