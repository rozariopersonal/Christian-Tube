import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';

/// The reader's bottom navigation bar: displays current reading progress and
/// provides manual previous/next page navigation buttons.
class ReaderNavigationBar extends StatelessWidget {
  final BookReaderController controller;
  final AppTokens tokens;
  final Color bgColor;
  final bool isDualPage;
  final int totalPages;
  final int validLeftPage;
  final int? rightPage;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const ReaderNavigationBar({
    super.key,
    required this.controller,
    required this.tokens,
    required this.bgColor,
    required this.isDualPage,
    required this.totalPages,
    required this.validLeftPage,
    required this.rightPage,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final appearance = controller.appearance;
    final textCol = appearance.textColor(tokens);
    final mutedCol = appearance.mutedTextColor(tokens);
    final borderCol = appearance.surfaceBorder(tokens);

    final canGoPrev = isDualPage ? s.spreadLeftPage > 1 : s.currentPage > 1;
    final canGoNext = isDualPage
        ? (rightPage != null && rightPage! < totalPages)
        : s.currentPage < totalPages;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: borderCol, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1.0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 28),
                      color: canGoPrev ? textCol : mutedCol.withValues(alpha: 0.35),
                      onPressed: canGoPrev ? onPrevious : null,
                      tooltip: 'Previous',
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (controller.currentChapterTitle().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                controller.currentChapterTitle(),
                                style: TextStyle(
                                  color: textCol,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Builder(builder: (context) {
                            if (isDualPage) {
                              final displayRight = validLeftPage + 1 <= totalPages ? validLeftPage + 1 : null;
                              return Text(
                                'Pages $validLeftPage–${displayRight ?? validLeftPage} of $totalPages • ${(s.lastPercent * 100).toInt()}%',
                                style: TextStyle(color: mutedCol, fontSize: 11.5),
                              );
                            } else {
                              return Text(
                                'Page ${s.currentPage} of $totalPages • ${(s.lastPercent * 100).toInt()}%',
                                style: TextStyle(color: mutedCol, fontSize: 11.5),
                              );
                            }
                          }),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 28),
                      color: canGoNext ? textCol : mutedCol.withValues(alpha: 0.35),
                      onPressed: canGoNext ? onNext : null,
                      tooltip: 'Next',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

