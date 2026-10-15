import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';

/// Modal bottom sheet displaying options for an individual book (remove download, download, etc.).
class BookOptionsSheet extends StatelessWidget {
  final Book book;
  final bool isInstalled;
  final VoidCallback onRemoveDownload;
  final VoidCallback onDownload;

  const BookOptionsSheet({
    super.key,
    required this.book,
    required this.isInstalled,
    required this.onRemoveDownload,
    required this.onDownload,
  });

  static Future<void> show(
    BuildContext context, {
    required Book book,
    required bool isInstalled,
    required VoidCallback onRemoveDownload,
    required VoidCallback onDownload,
  }) {
    final tokens = context.tokens;
    return showAdaptiveBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BookOptionsSheet(
        book: book,
        isInstalled: isInstalled,
        onRemoveDownload: () {
          Navigator.of(ctx).pop();
          onRemoveDownload();
        },
        onDownload: () {
          Navigator.of(ctx).pop();
          onDownload();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: tokens.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              book.title,
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'By ${book.author} • ${book.subject}',
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (!kIsWeb)
              if (isInstalled)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  title: Text('Remove Download',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  subtitle: Text(
                    'Frees storage. Notes and reading progress are preserved.',
                    style: TextStyle(
                        color: tokens.onSurfaceMuted, fontSize: 13),
                  ),
                  onTap: onRemoveDownload,
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_rounded, color: tokens.accent),
                  title: Text('Download Book (${book.downloadSizeFormatted})',
                      style: TextStyle(color: tokens.onSurface)),
                  onTap: onDownload,
                ),
          ],
        ),
      ),
    );
  }
}
