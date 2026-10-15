import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/api/github_data_service.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';

/// Modal bottom sheet prompting download of an individual book for offline reading.
class BookDownloadSingleSheet extends StatelessWidget {
  final Book book;
  final String downloadAllLabel;
  final VoidCallback onDownloadSingle;
  final VoidCallback onDownloadAll;

  const BookDownloadSingleSheet({
    super.key,
    required this.book,
    required this.downloadAllLabel,
    required this.onDownloadSingle,
    required this.onDownloadAll,
  });

  /// Displays the adaptive bottom sheet and resolves with true if single download was tapped,
  /// false if download-all was chosen, or null if dismissed.
  static Future<bool?> show(
    BuildContext context, {
    required Book book,
    required String downloadAllLabel,
    required VoidCallback onDownloadAll,
  }) {
    final tokens = context.tokens;
    return showAdaptiveBottomSheet<bool>(
      context: context,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BookDownloadSingleSheet(
        book: book,
        downloadAllLabel: downloadAllLabel,
        onDownloadSingle: () => Navigator.of(ctx).pop(true),
        onDownloadAll: () {
          Navigator.of(ctx).pop(false);
          onDownloadAll();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sizeText = book.downloadSizeFormatted.isNotEmpty
        ? book.downloadSizeFormatted
        : 'under 100 KB';

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
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 44,
                    height: 64,
                    color: tokens.surfaceVariant,
                    child: book.coverFile.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl:
                                GitHubDataService.bookCoverUrl(book.coverFile),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: tokens.surfaceVariant,
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tokens.accent.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) =>
                                Icon(Icons.menu_book, color: tokens.accent),
                          )
                        : Icon(Icons.menu_book, color: tokens.accent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${book.author} • ${book.subject}',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${book.totalPages} pages • $sizeText',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Download this book for instant offline reading. Fast download (~$sizeText).',
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onDownloadSingle,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Download & Read ($sizeText)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: onDownloadAll,
                icon: Icon(Icons.all_inclusive_rounded,
                    color: tokens.onSurfaceMuted, size: 16),
                label: Text(
                  downloadAllLabel,
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
