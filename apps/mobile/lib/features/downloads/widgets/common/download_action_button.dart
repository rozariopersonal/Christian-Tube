import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Standardized action button for downloading, tracking progress, and removing
/// items in the offline library.
class DownloadActionButton extends StatelessWidget {
  final bool isInstalled;
  final bool isDownloading;
  final double progress;
  final bool isIndeterminate;
  final bool isProtected;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final String downloadLabel;

  const DownloadActionButton({
    super.key,
    required this.isInstalled,
    required this.isDownloading,
    this.progress = 0.0,
    this.isIndeterminate = false,
    this.isProtected = false,
    required this.onDownload,
    required this.onDelete,
    this.downloadLabel = 'Download',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (isProtected) {
      return Tooltip(
        message: 'Protected base translation (cannot be deleted)',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(Icons.verified_user_rounded, color: tokens.accent, size: 20),
        ),
      );
    }

    if (isInstalled) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
        tooltip: 'Remove from device',
        visualDensity: VisualDensity.compact,
        onPressed: onDelete,
      );
    }

    if (isDownloading) {
      final text = (!isIndeterminate && progress > 0)
          ? '${(progress * 100).toInt()}%'
          : 'Downloading…';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.accent,
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
          ),
        ),
      );
    }

    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onDownload,
      child: Text(downloadLabel, style: const TextStyle(fontSize: 12)),
    );
  }
}
