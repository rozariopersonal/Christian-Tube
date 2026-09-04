import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';

/// The book reader's top app bar.
///
/// Renders the title (plus chapter/page subtitle in dual-page mode) and a
/// collapse-aware action row: on very narrow screens trailing actions collapse
/// into an overflow [PopupMenuButton] to avoid overflow at 320dp (per the
/// Responsive & Adaptive UI Standard).
class BookReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BookReaderController controller;
  final AppTokens tokens;
  final Color bgColor;
  final bool isDualPage;
  final int validLeftPage;
  final int? rightPage;
  final int totalPages;
  final VoidCallback onOpenToc;
  final VoidCallback onOpenHighlights;
  final VoidCallback onShowAppearance;

  const BookReaderAppBar({
    super.key,
    required this.controller,
    required this.tokens,
    required this.bgColor,
    required this.isDualPage,
    required this.validLeftPage,
    required this.rightPage,
    required this.totalPages,
    required this.onOpenToc,
    required this.onOpenHighlights,
    required this.onShowAppearance,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final appearance = controller.appearance;
    final chapterTitle = controller.currentChapterTitle();

    return AppBar(
      backgroundColor: bgColor.withValues(alpha: 0.8),
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(color: Colors.transparent),
        ),
      ),
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.book?.title ?? 'Book Reader',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: appearance.textColor(tokens),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          if (isDualPage)
            Text(
              chapterTitle.isNotEmpty
                  ? '$chapterTitle • Pages $validLeftPage–${rightPage ?? validLeftPage} of $totalPages'
                  : 'Pages $validLeftPage–${rightPage ?? validLeftPage} of $totalPages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appearance.mutedTextColor(tokens), fontSize: 11.5),
            )
          else if (chapterTitle.isNotEmpty)
            Text(
              chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appearance.mutedTextColor(tokens), fontSize: 11.5),
            ),
        ],
      ),
      actions: MediaQuery.sizeOf(context).width < 360
          ? [
              IconButton(
                icon: Icon(Icons.list_alt_rounded, color: tokens.onSurfaceMuted, size: 21),
                tooltip: 'Table of contents',
                onPressed: onOpenToc,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: tokens.onSurfaceMuted, size: 21),
                tooltip: 'More options',
                onSelected: (val) {
                  if (val == 'highlights') onOpenHighlights();
                  if (val == 'appearance') onShowAppearance();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'highlights',
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded, color: tokens.accent, size: 20),
                        const SizedBox(width: 12),
                        const Text('Highlights & Notes'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'appearance',
                    child: Row(
                      children: [
                        Icon(Icons.text_fields_rounded, color: tokens.onSurfaceMuted, size: 20),
                        const SizedBox(width: 12),
                        const Text('Reading settings'),
                      ],
                    ),
                  ),
                ],
              ),
            ]
          : [
              IconButton(
                icon: Icon(Icons.edit_note_rounded, color: tokens.accent, size: 22),
                tooltip: 'Highlights & Notes',
                onPressed: onOpenHighlights,
              ),
              IconButton(
                icon: Icon(Icons.text_fields_rounded, color: tokens.onSurfaceMuted, size: 21),
                tooltip: 'Reading settings',
                onPressed: onShowAppearance,
              ),
              IconButton(
                icon: Icon(Icons.list_alt_rounded, color: tokens.onSurfaceMuted, size: 21),
                tooltip: 'Table of contents',
                onPressed: onOpenToc,
              ),
            ],
    );
  }
}
