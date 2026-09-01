import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book_chapter.dart';

/// Modal bottom sheet or dialog displaying the Table of Contents for a book.
class BookTocSheet extends StatelessWidget {
  final String bookTitle;
  final List<BookChapter> chapters;
  final int currentPage;
  final ValueChanged<int> onSelectPage;
  final bool showPageNumbers;

  const BookTocSheet({
    super.key,
    required this.bookTitle,
    required this.chapters,
    required this.currentPage,
    required this.onSelectPage,
    this.showPageNumbers = true,
  });

  static Future<void> show(
    BuildContext context, {
    required String bookTitle,
    required List<BookChapter> chapters,
    required int currentPage,
    required ValueChanged<int> onSelectPage,
    bool showPageNumbers = true,
  }) {
    final tokens = context.tokens;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MaxWidthBox(
        maxWidth: 640,
        child: BookTocSheet(
          bookTitle: bookTitle,
          chapters: chapters,
          currentPage: currentPage,
          onSelectPage: onSelectPage,
          showPageNumbers: showPageNumbers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.list_alt_rounded, color: tokens.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Table of Contents',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Chapter list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final ch = chapters[index];
                  final isCurrent = currentPage >= ch.startPage && currentPage <= ch.endPage;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    tileColor: isCurrent ? tokens.accent.withValues(alpha: 0.12) : null,
                    leading: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? tokens.accent
                            : tokens.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${ch.chapterIndex}',
                        style: TextStyle(
                          color: isCurrent ? Colors.white : tokens.onSurfaceMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      ch.chapterTitle,
                      style: TextStyle(
                        color: isCurrent ? tokens.accent : tokens.onSurface,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    trailing: showPageNumbers
                        ? Text(
                            'p. ${ch.startPage}',
                            style: TextStyle(
                              color: isCurrent ? tokens.accent : tokens.onSurfaceMuted,
                              fontSize: 12,
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelectPage(ch.startPage);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
