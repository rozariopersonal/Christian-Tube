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
    final muted = appearance.mutedTextColor(tokens);

    final canGoPrev = isDualPage ? s.spreadLeftPage > 1 : s.currentPage > 1;
    final canGoNext = isDualPage
        ? (rightPage != null && rightPage! < totalPages)
        : s.currentPage < totalPages;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          color: bgColor.withValues(alpha: 0.8),
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
                      color: canGoPrev ? tokens.onSurface : tokens.onSurfaceDisabled,
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
                                  color: tokens.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
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
                                style: TextStyle(color: muted, fontSize: 11.5),
                              );
                            } else {
                              return Text(
                                'Page ${s.currentPage} of $totalPages • ${(s.lastPercent * 100).toInt()}%',
                                style: TextStyle(color: muted, fontSize: 11.5),
                              );
                            }
                          }),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 28),
                      color: canGoNext ? tokens.onSurface : tokens.onSurfaceDisabled,
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

