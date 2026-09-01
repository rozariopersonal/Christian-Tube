import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';
import '../models/user_reading_progress.dart';
import 'book_cover_fallback.dart';

/// Card displaying a single book in the library grid.
/// Shows cover artwork (with fallback jacket) and reading progress indicator.
class BookCard extends StatelessWidget {
  final Book book;
  final UserReadingProgress? progress;
  final VoidCallback? onTap;

  const BookCard({
    super.key,
    required this.book,
    this.progress,
    this.onTap,
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
          // Cover surface with progress bar overlay
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildCover(context),
                ),
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
          const SizedBox(height: 8),

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
