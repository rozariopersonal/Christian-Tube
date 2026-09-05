import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';
import '../widgets/verse_action_bar.dart';
import '../controllers/bible_controller.dart';

class BibleBottomNav extends StatelessWidget {
  const BibleBottomNav({
    super.key,
    required this.controller,
    required this.onShowBookChapterSelector,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    required this.onStudy,
  });

  final BibleController controller;
  final VoidCallback onShowBookChapterSelector;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final VoidCallback? onStudy;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    if (s.selectedVerses.isNotEmpty) {
      return VerseActionBar(
        selectedCount: s.selectedVerses.length,
        onCopy: onCopy,
        onShare: onShare,
        onBookmark: onBookmark,
        onClear: onClear,
        onStudy: onStudy,
      );
    }
    return _ChapterNav(
      canFetchPrev: s.canFetchPrev,
      canFetchNext: s.canFetchNext,
      onPrev: controller.fetchPrevChapter,
      onNext: controller.fetchNextChapter,
      onShowBookChapterSelector: onShowBookChapterSelector,
      currentBookLabel:
          '${controller.displayBookName(controller.currentBook)} '
          '${controller.currentChapter}',
    );
  }
}

class _ChapterNav extends StatelessWidget {
  const _ChapterNav({
    required this.canFetchPrev,
    required this.canFetchNext,
    required this.onPrev,
    required this.onNext,
    required this.onShowBookChapterSelector,
    required this.currentBookLabel,
  });

  final bool canFetchPrev;
  final bool canFetchNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShowBookChapterSelector;
  final String currentBookLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: context.tokens.background,
        boxShadow: [
          BoxShadow(
            color: context.tokens.scrim.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: MaxWidthBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Semantics(
                label: 'Previous chapter',
                button: true,
                child: IconButton(
                  onPressed: canFetchPrev ? onPrev : null,
                  tooltip: 'Previous chapter',
                  icon: const Icon(Icons.chevron_left_rounded, size: 30),
                  color: canFetchPrev
                      ? context.tokens.onSurface
                      : context.tokens.onSurfaceDisabled,
                ),
              ),
              Expanded(
                child: Center(
                  child: Semantics(
                    label: 'Book and chapter selector: $currentBookLabel',
                    button: true,
                    child: InkWell(
                      onTap: onShowBookChapterSelector,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                currentBookLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 2),
                              child: Icon(Icons.arrow_drop_down, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                label: 'Next chapter',
                button: true,
                child: IconButton(
                  onPressed: canFetchNext ? onNext : null,
                  tooltip: 'Next chapter',
                  icon: const Icon(Icons.chevron_right_rounded, size: 30),
                  color: canFetchNext
                      ? context.tokens.onSurface
                      : context.tokens.onSurfaceDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
