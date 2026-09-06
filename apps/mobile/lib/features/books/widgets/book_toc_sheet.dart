import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book_chapter.dart';

/// Modal bottom sheet or dialog displaying the Table of Contents and Subtitles for a book.
class BookTocSheet extends StatefulWidget {
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
  State<BookTocSheet> createState() => _BookTocSheetState();
}

class _BookTocSheetState extends State<BookTocSheet> {
  final Set<int> _expandedChapters = {};

  @override
  void initState() {
    super.initState();
    // Automatically expand the chapter that contains the current page
    for (final ch in widget.chapters) {
      if (widget.currentPage >= ch.startPage && widget.currentPage <= ch.endPage) {
        if (ch.subtitles.isNotEmpty) {
          _expandedChapters.add(ch.chapterIndex);
        }
        break;
      }
    }
  }

  void _toggleChapter(int chapterIndex) {
    setState(() {
      if (_expandedChapters.contains(chapterIndex)) {
        _expandedChapters.remove(chapterIndex);
      } else {
        _expandedChapters.add(chapterIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
                          widget.bookTitle,
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

            // Chapter & Subtitle list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.chapters.length,
                itemBuilder: (context, index) {
                  final ch = widget.chapters[index];
                  final isCurrentChapter =
                      widget.currentPage >= ch.startPage && widget.currentPage <= ch.endPage;
                  final hasSubtitles = ch.subtitles.isNotEmpty;
                  final isExpanded = _expandedChapters.contains(ch.chapterIndex);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chapter item
                      InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onSelectPage(ch.startPage);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: isCurrentChapter
                              ? tokens.accent.withValues(alpha: 0.1)
                              : null,
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCurrentChapter
                                      ? tokens.accent
                                      : tokens.surfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${ch.chapterIndex}',
                                  style: TextStyle(
                                    color: isCurrentChapter
                                        ? Colors.white
                                        : tokens.onSurfaceMuted,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ch.chapterTitle,
                                      style: TextStyle(
                                        color: isCurrentChapter
                                            ? tokens.accent
                                            : tokens.onSurface,
                                        fontWeight: isCurrentChapter
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (hasSubtitles) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '${ch.subtitles.length} sections',
                                        style: TextStyle(
                                          color: tokens.onSurfaceMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (widget.showPageNumbers) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'p. ${ch.startPage}',
                                  style: TextStyle(
                                    color: isCurrentChapter
                                        ? tokens.accent
                                        : tokens.onSurfaceMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (hasSubtitles) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(
                                    isExpanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    color: tokens.onSurfaceMuted,
                                    size: 20,
                                  ),
                                  onPressed: () => _toggleChapter(ch.chapterIndex),
                                  tooltip: isExpanded ? 'Collapse sections' : 'Show sections',
                                ),
                              ] else ...[
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Subtitles under chapter
                      if (hasSubtitles && isExpanded)
                        Container(
                          margin: const EdgeInsets.only(left: 28, right: 12, top: 2, bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: isCurrentChapter
                                    ? tokens.accent.withValues(alpha: 0.4)
                                    : tokens.surfaceBorder,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Column(
                            children: ch.subtitles.asMap().entries.map((entry) {
                              final subIdx = entry.key;
                              final sub = entry.value;

                              // Determine if current page is within this subtitle's range
                              final nextSub = (subIdx + 1 < ch.subtitles.length)
                                  ? ch.subtitles[subIdx + 1]
                                  : null;
                              final isCurrentSub = widget.currentPage >= sub.pageNumber &&
                                  (nextSub == null
                                      ? widget.currentPage <= ch.endPage
                                      : widget.currentPage < nextSub.pageNumber);

                              return InkWell(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onSelectPage(sub.pageNumber);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isCurrentSub
                                            ? Icons.play_arrow_rounded
                                            : Icons.circle,
                                        size: isCurrentSub ? 14 : 6,
                                        color: isCurrentSub
                                            ? tokens.accent
                                            : tokens.onSurfaceMuted,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          sub.title,
                                          style: TextStyle(
                                            color: isCurrentSub
                                                ? tokens.accent
                                                : tokens.onSurface,
                                            fontWeight: isCurrentSub
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (widget.showPageNumbers) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          'p. ${sub.pageNumber}',
                                          style: TextStyle(
                                            color: isCurrentSub
                                                ? tokens.accent
                                                : tokens.onSurfaceMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
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
