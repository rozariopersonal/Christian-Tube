import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';

/// Micro action button displaying the download, downloading progress, or installed/delete state
/// of a font family.
class FontDownloadActionButton extends StatelessWidget {
  final String family;
  final bool isInstalled;
  final bool isLoading;
  final bool showDeleteWhenInstalled;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const FontDownloadActionButton({
    super.key,
    required this.family,
    required this.isInstalled,
    required this.isLoading,
    this.showDeleteWhenInstalled = false,
    this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (isLoading) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
          ),
        ),
      );
    }

    if (isInstalled) {
      if (showDeleteWhenInstalled) {
        return IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 20, color: tokens.onSurfaceMuted),
          tooltip: 'Delete font from device',
          onPressed: onDelete ??
              () {
                ReaderFontsService.instance.deleteFont(family);
              },
        );
      }
      return Tooltip(
        message: 'Offline ready',
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: tokens.accent,
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(Icons.cloud_download_outlined, size: 20, color: tokens.accent),
      tooltip: 'Download font for offline reading',
      onPressed: onDownload ??
          () {
            ReaderFontsService.instance.ensureFamily(family);
          },
    );
  }
}
