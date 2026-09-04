import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';
import '../widgets/verse_action_bar.dart';
import '../controllers/bible_controller.dart';

class BibleBottomNav extends StatelessWidget {
  const BibleBottomNav({
    super.key,
    required this.controller,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    required this.onStudy,
  });

  final BibleController controller;
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
    );
  }
}

class _ChapterNav extends StatelessWidget {
  const _ChapterNav({
    required this.canFetchPrev,
    required this.canFetchNext,
    required this.onPrev,
    required this.onNext,
  });

  final bool canFetchPrev;
  final bool canFetchNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Semantics(
                label: 'Previous chapter',
                button: true,
                child: TextButton.icon(
                  onPressed: canFetchPrev ? onPrev : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
              ),
              Semantics(
                label: 'Next chapter',
                button: true,
                child: TextButton.icon(
                  onPressed: canFetchNext ? onNext : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                  iconAlignment: IconAlignment.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
