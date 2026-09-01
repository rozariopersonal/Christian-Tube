import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';
import '../models/user_reading_progress.dart';
import 'book_cover_fallback.dart';

/// Card displaying a single book in the library grid.
/// Shows cover artwork (with fallback jacket), author, subject, reading progress, and download status.
class BookCard extends StatelessWidget {
  final Book book;
  final UserReadingProgress? progress;
  final bool isInstalled;
  final bool isDownloading;
  final VoidCallback? onTap;
  final VoidCallback? onDownloadTap;

  const BookCard({
    super.key,
    required this.book,
    this.progress,
    this.isInstalled = false,
    this.isDownloading = false,
    this.onTap,
    this.onDownloadTap,
  });

  Widget _buildCover(BuildContext context) {
    final tokens = context.tokens;
    final coverFile = book.coverFile;

    if (coverFile.isNotEmpty) {
      final assetPath = 'assets/books/covers/$coverFile';
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.surfaceBorder.withValues(alpha: 0.4),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: tokens.scrim.withValues(alpha: 0.25),
                blurRadius: 5,
                offset: const Offset(1, 3),
              ),
            ],
          ),
          child: Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => BookCoverFallback(
              title: book.title,
              author: book.author,
            ),
          ),
        ),
      );
    }

    return BookCoverFallback(
      title: book.title,
      author: book.author,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final percent = progress?.completionPercent ?? 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover surface with progress bar and download status overlay
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildCover(context),
                ),

                // Download / Installed Badge
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: tokens.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.scrim.withValues(alpha: 0.2),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: isDownloading
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                            ),
                          )
                        : isInstalled
                            ? Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: tokens.accent,
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 11,
                                    color: tokens.onSurfaceMuted,
                                  ),
                                  if (book.downloadSizeFormatted.isNotEmpty) ...[
                                    const SizedBox(width: 2),
                                    Text(
                                      book.downloadSizeFormatted,
                                      style: TextStyle(
                                        color: tokens.onSurfaceMuted,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                  ),
                ),

                // Reading Progress bar
                if (percent > 0.0)
                  Positioned(
                    left: 2,
                    right: 2,
                    bottom: 2,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(7),
                        bottomRight: Radius.circular(7),
                      ),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 4,
                        backgroundColor: tokens.background.withValues(alpha: 0.6),
                        valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),

          // Subject Tag
          if (book.subject.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                book.subject.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),

          // Title
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),

          // Author & Page count
          Row(
            children: [
              Expanded(
                child: Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (percent > 0.0)
                Text(
                  '${(percent * 100).toInt()}%',
                  style: TextStyle(
                    color: tokens.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 10.5,
                  ),
                )
              else
                Text(
                  '${book.totalPages}p',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 10.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
