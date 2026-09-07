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

    final isDark = appearance.isDark(tokens);
    final textCol = appearance.textColor(tokens);
    final mutedCol = appearance.mutedTextColor(tokens);
    final width = MediaQuery.sizeOf(context).width;

    return AppBar(
      backgroundColor: bgColor.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: textCol),
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
              color: textCol,
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
              style: TextStyle(color: mutedCol, fontSize: 11.5),
            )
          else if (chapterTitle.isNotEmpty)
            Text(
              chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: mutedCol, fontSize: 11.5),
            ),
        ],
      ),
      actions: width < 380
          ? [
              IconButton(
                icon: Icon(Icons.list_alt_rounded, color: mutedCol, size: 21),
                tooltip: 'Table of contents',
                onPressed: onOpenToc,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: mutedCol, size: 21),
                color: appearance.surface(tokens),
                tooltip: 'More options',
                onSelected: (val) {
                  if (val == 'toggle_dark') appearance.toggleDarkMode(tokens);
                  if (val == 'highlights') onOpenHighlights();
                  if (val == 'appearance') onShowAppearance();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'toggle_dark',
                    child: Row(
                      children: [
                        Icon(
                          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          color: tokens.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                          style: TextStyle(color: textCol),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'highlights',
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded, color: tokens.accent, size: 20),
                        const SizedBox(width: 12),
                        Text('Highlights & Notes', style: TextStyle(color: textCol)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'appearance',
                    child: Row(
                      children: [
                        Icon(Icons.text_fields_rounded, color: mutedCol, size: 20),
                        const SizedBox(width: 12),
                        Text('Reading settings', style: TextStyle(color: textCol)),
                      ],
                    ),
                  ),
                ],
              ),
            ]
          : [
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: textCol,
                  size: 21,
                ),
                tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                onPressed: () => appearance.toggleDarkMode(tokens),
              ),
              IconButton(
                icon: Icon(Icons.edit_note_rounded, color: tokens.accent, size: 22),
                tooltip: 'Highlights & Notes',
                onPressed: onOpenHighlights,
              ),
              IconButton(
                icon: Icon(Icons.text_fields_rounded, color: mutedCol, size: 21),
                tooltip: 'Reading settings',
                onPressed: onShowAppearance,
              ),
              IconButton(
                icon: Icon(Icons.list_alt_rounded, color: mutedCol, size: 21),
                tooltip: 'Table of contents',
                onPressed: onOpenToc,
              ),
            ],
    );
  }
}
