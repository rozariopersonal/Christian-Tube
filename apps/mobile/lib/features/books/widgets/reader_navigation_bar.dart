import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';

/// The reader's bottom navigation bar: a progress slider with page navigation
/// for both single-page scroll mode and the dual-page spread mode.
///
/// Pure presentational component. Slider drag/focus state is owned by the
/// parent (it carries live scroll geometry), forwarded in via [sliderDragPercent]
/// and [sliderDragSpreadPage] and pushed back out through the setter callbacks.
class ReaderNavigationBar extends StatelessWidget {
  final BookReaderController controller;
  final AppTokens tokens;
  final Color bgColor;
  final bool isDualPage;
  final int totalPages;
  final int validLeftPage;
  final int? rightPage;
  final double? sliderDragPercent;
  final int? sliderDragSpreadPage;
  final void Function(int delta) turnSpread;
  final void Function(int page) jumpToPage;
  final void Function(double? value) setSliderDragPercent;
  final void Function(int? value) setSliderDragSpreadPage;

  const ReaderNavigationBar({
    super.key,
    required this.controller,
    required this.tokens,
    required this.bgColor,
    required this.isDualPage,
    required this.totalPages,
    required this.validLeftPage,
    required this.rightPage,
    required this.sliderDragPercent,
    required this.sliderDragSpreadPage,
    required this.turnSpread,
    required this.jumpToPage,
    required this.setSliderDragPercent,
    required this.setSliderDragSpreadPage,
  });

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final appearance = controller.appearance;
    final muted = appearance.mutedTextColor(tokens);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          color: bgColor.withValues(alpha: 0.8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDualPage) ...[
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: s.spreadLeftPage > 1 ? tokens.onSurface : tokens.onSurfaceDisabled,
                    onPressed: s.spreadLeftPage > 1 ? () => turnSpread(-2) : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: (sliderDragSpreadPage ?? validLeftPage).toDouble().clamp(1.0, totalPages.toDouble()),
                      min: 1.0,
                      max: totalPages.toDouble(),
                      activeColor: tokens.accent,
                      onChanged: (val) => setSliderDragSpreadPage(val.toInt()),
                      onChangeEnd: (val) {
                        setSliderDragSpreadPage(null);
                        jumpToPage(val.toInt());
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: rightPage != null && rightPage! < totalPages
                        ? tokens.onSurface
                        : tokens.onSurfaceDisabled,
                    onPressed: rightPage != null && rightPage! < totalPages ? () => turnSpread(2) : null,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Builder(builder: (context) {
                  final displayLeft = sliderDragSpreadPage ?? validLeftPage;
                  final displayRight = displayLeft + 1 <= totalPages ? displayLeft + 1 : null;
                  return Text(
                    'Pages $displayLeft–${displayRight ?? displayLeft} of $totalPages • ${(s.lastPercent * 100).toInt()}% complete',
                    style: TextStyle(color: muted, fontSize: 11.5),
                  );
                }),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: (sliderDragPercent ?? s.lastPercent).clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      activeColor: tokens.accent,
                      onChanged: setSliderDragPercent,
                      onChangeEnd: (val) {
                        final targetPage = ((val * totalPages).round()).clamp(1, totalPages);
                        jumpToPage(targetPage);
                        setSliderDragPercent(null);
                      },
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  controller.currentChapterTitle().isNotEmpty
                      ? '${controller.currentChapterTitle()} • ${(((sliderDragPercent ?? s.lastPercent) * 100).toInt())}% complete'
                      : '${(((sliderDragPercent ?? s.lastPercent) * 100).toInt())}% complete',
                  style: TextStyle(color: muted, fontSize: 11.5),
                ),
              ),
            ],
          ],
        ),
      ),
        ),
      ),
    );
  }
}
