import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';
import '../../../shared/services/reader_appearance.dart';
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
    required this.onHighlight,
    required this.onNote,
    required this.onClear,
    required this.onStudy,
    this.studyContent,
    this.onStageChanged,
  });

  final BibleController controller;
  final VoidCallback onShowBookChapterSelector;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback onClear;
  final VoidCallback? onStudy;
  final Widget? studyContent;
  final ValueChanged<VerseSheetStage>? onStageChanged;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final appearance = controller.appearance;

    if (s.selectedVerses.isNotEmpty) {
      final book = s.selectedBook ?? controller.currentBook;
      final chapter = s.selectedChapter ?? controller.currentChapter;
      final sortedVerses = s.selectedVerses.toList()..sort();
      final verseLabel = sortedVerses.length == 1
          ? '${controller.displayBookName(book)} $chapter:${sortedVerses.first}'
          : '${controller.displayBookName(book)} $chapter:${sortedVerses.first}-${sortedVerses.last} (${sortedVerses.length} verses)';

      return VerseActionBar(
        selectedCount: s.selectedVerses.length,
        appearance: appearance,
        onCopy: onCopy,
        onShare: onShare,
        onBookmark: onBookmark,
        onHighlight: onHighlight,
        onHighlightColor: (color) => controller.applyHighlight(color),
        onRemoveHighlight: () => controller.removeHighlight(),
        currentColorIndex: s.highlightColorForSelection,
        hasHighlight: s.selectionHasHighlight,
        verseLabel: verseLabel,
        studyContent: studyContent,
        onNote: onNote,
        onClear: onClear,
        onStudy: onStudy,
        onStageChanged: onStageChanged,
      );
    }
    return _ChapterNav(
      appearance: appearance,
      canFetchPrev: s.canFetchPrev,
      canFetchNext: s.canFetchNext,
      onPrev: controller.fetchPrevChapter,
      onNext: controller.fetchNextChapter,
      onShowBookChapterSelector: onShowBookChapterSelector,
      currentBookLabel: '${controller.displayBookName(controller.currentBook)} '
          '${controller.currentChapter}',
    );
  }
}

class _ChapterNav extends StatelessWidget {
  const _ChapterNav({
    required this.appearance,
    required this.canFetchPrev,
    required this.canFetchNext,
    required this.onPrev,
    required this.onNext,
    required this.onShowBookChapterSelector,
    required this.currentBookLabel,
  });

  final ReaderAppearance appearance;
  final bool canFetchPrev;
  final bool canFetchNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShowBookChapterSelector;
  final String currentBookLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = context.accent;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    final mutedCol = onAccent.withValues(alpha: 0.78);
    final disabledCol = onAccent.withValues(alpha: 0.38);

    return Container(
      color: appearance.background(tokens),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Center(
            child: MaxWidthBox(
              maxWidth: 420,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.scrim.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Previous chapter',
                        button: true,
                        child: IconButton(
                          onPressed: canFetchPrev ? onPrev : null,
                          tooltip: 'Previous chapter',
                          icon: const Icon(Icons.chevron_left_rounded, size: 28),
                          color: canFetchPrev ? onAccent : disabledCol,
                          splashRadius: 20,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Semantics(
                            label: 'Book and chapter selector: $currentBookLabel',
                            button: true,
                            child: InkWell(
                              onTap: onShowBookChapterSelector,
                              borderRadius: BorderRadius.circular(20),
                              splashColor: onAccent.withValues(alpha: 0.16),
                              highlightColor: onAccent.withValues(alpha: 0.12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        currentBookLabel,
                                        style: TextStyle(
                                          color: onAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Icon(
                                        Icons.arrow_drop_down,
                                        size: 20,
                                        color: mutedCol,
                                      ),
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
                          icon: const Icon(Icons.chevron_right_rounded, size: 28),
                          color: canFetchNext ? onAccent : disabledCol,
                          splashRadius: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
