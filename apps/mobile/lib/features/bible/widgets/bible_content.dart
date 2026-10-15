import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../models/bible_verse.dart';
import '../services/bible_chapter_stream.dart';
import '../widgets/verse_item.dart';
import '../controllers/bible_controller.dart';
import '../../../shared/services/reader_appearance.dart';
import '../../../core/services/bottom_bar_visibility_service.dart';

class BibleContent extends StatelessWidget {
  const BibleContent({
    super.key,
    required this.controller,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.onVerseTap,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    required this.onOpenStudyPage,
    required this.onPushManager,
    required this.onRedownloadDefault,
  });

  final BibleController controller;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final void Function(int verseNumber, {String? book, int? chapter}) onVerseTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final void Function(int verseNumber, {int initialTab, String? book, int? chapter}) onOpenStudyPage;
  final VoidCallback onPushManager;
  final VoidCallback onRedownloadDefault;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    if (s.isLoading) return const Center(child: CircularProgressIndicator());
    if (s.versions.isEmpty) return _EmptyState(onPushManager: onPushManager);
    if (s.chapterEmpty || s.totalRows == 0) {
      return _ChapterEmptyState(
        controller: controller,
        onRedownloadDefault: onRedownloadDefault,
      );
    }
    final verseIndex = s.index;
    final itemCount = s.totalRows;
    final isWholeBible = verseIndex != null;
    return MaxWidthBox(
      maxWidth: kReadingMaxWidth,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            SystemChannels.textInput.invokeMethod('TextInput.hide');
            // Selection persists across scrolls and is never auto-cleared.
          }
          if ((notification is UserScrollNotification &&
                  notification.direction != ScrollDirection.idle) ||
              (notification is ScrollUpdateNotification &&
                  notification.dragDetails != null &&
                  notification.scrollDelta != null &&
                  notification.scrollDelta!.abs() > 2)) {
            BottomBarVisibilityService.instance.hideBibleNav();
          }
          return false;
        },
        child: ScrollablePositionedList.builder(
          itemScrollController: itemScrollController,
          itemPositionsListener: itemPositionsListener,
          itemCount: itemCount,
          minCacheExtent: 300,
          padding: const EdgeInsets.only(top: 16, bottom: 128),
          itemBuilder: (context, index) {
              if (index < 0 || index >= itemCount) return const SizedBox.shrink();
              if (!isWholeBible) {
                if (index >= s.verses.length) return const SizedBox.shrink();
                final verse = s.verses[index];
                final verseWidget = _VerseRow(
                  verse: verse,
                  book: controller.currentBook,
                  chapter: controller.currentChapter,
                  controller: controller,
                  onVerseTap: onVerseTap,
                  onCopy: onCopy,
                  onShare: onShare,
                  onBookmark: onBookmark,
                  onClear: onClear,
                  onOpenStudyPage: onOpenStudyPage,
                );
                if (index == 0 || verse.number == 1) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ChapterHeader(
                        chapter: controller.currentChapter,
                        appearance: controller.appearance,
                        bookName: controller.displayBookName(controller.currentBook),
                        chapterTitle: controller.displayChapterTitle(controller.currentChapter),
                        isBookStart: controller.currentChapter == 1,
                      ),
                      verseWidget,
                    ],
                  );
                }
                return verseWidget;
              }
              final ref = verseIndex.rowToReference(index);
              final rows =
                  s.loadedChapters[bibleChapterId(ref.bookNumber, ref.chapter)];
              if (rows == null) {
                controller.ensureChapterVisible(ref.bookNumber, ref.chapter);
                if (ref.verse == 1) {
                  final bookName = BookNameService.englishNameFor(ref.bookNumber);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ChapterHeader(
                        chapter: ref.chapter,
                        appearance: controller.appearance,
                        bookName: controller.displayBookName(bookName),
                        chapterTitle: controller.displayChapterTitle(ref.chapter),
                        isBookStart: ref.chapter == 1,
                      ),
                      _PlaceholderRow(
                        key: ValueKey('ph-${ref.bookNumber}-${ref.chapter}-${ref.verse}'),
                        appearance: controller.appearance,
                      ),
                    ],
                  );
                }
                return _PlaceholderRow(
                  key: ValueKey('ph-${ref.bookNumber}-${ref.chapter}-${ref.verse}'),
                  appearance: controller.appearance,
                );
              }

              // Locate the matching verse. Combined verses render once at their
              // starting verse number; secondary verses covered by the span
              // shrink to avoid repeating the paragraph.
              BibleVerse? matchedVerse;
              for (final v in rows) {
                if (v.number == ref.verse) {
                  matchedVerse = v;
                  break;
                }
              }
              final bookName = BookNameService.englishNameFor(ref.bookNumber);
              if (matchedVerse == null) {
                if (ref.verse == 1) {
                  return _ChapterHeader(
                    chapter: ref.chapter,
                    appearance: controller.appearance,
                    bookName: controller.displayBookName(bookName),
                    chapterTitle: controller.displayChapterTitle(ref.chapter),
                    isBookStart: ref.chapter == 1,
                  );
                }
                return const SizedBox.shrink();
              }

              final verseWidget = _VerseRow(
                verse: matchedVerse,
                book: bookName,
                chapter: ref.chapter,
                controller: controller,
                onVerseTap: (v, {book, chapter}) {
                  if (controller.currentBook != bookName ||
                      controller.currentChapter != ref.chapter) {
                    controller.updateVisibleChapter(
                      ref.bookNumber,
                      ref.chapter,
                      verse: v,
                    );
                  }
                  onVerseTap(v, book: book ?? bookName, chapter: chapter ?? ref.chapter);
                },
                onCopy: onCopy,
                onShare: onShare,
                onBookmark: onBookmark,
                onClear: onClear,
                onOpenStudyPage: onOpenStudyPage,
              );
              if (ref.verse == 1) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ChapterHeader(
                      chapter: ref.chapter,
                      appearance: controller.appearance,
                      bookName: controller.displayBookName(bookName),
                      chapterTitle: controller.displayChapterTitle(ref.chapter),
                      isBookStart: ref.chapter == 1,
                    ),
                    verseWidget,
                  ],
                );
              }
              return verseWidget;
            },
          ),
        ),
      );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.verse,
    required this.book,
    required this.chapter,
    required this.controller,
    required this.onVerseTap,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    required this.onOpenStudyPage,
  });

  final BibleVerse verse;
  final String book;
  final int chapter;
  final BibleController controller;
  final void Function(int verseNumber, {String? book, int? chapter}) onVerseTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final void Function(int verseNumber, {int initialTab, String? book, int? chapter}) onOpenStudyPage;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final highlightKey =
        BibleControllerState.verseHighlightKey(
      book,
      chapter,
      verse.number,
    );
    final isCurrentCh =
        book == controller.currentBook && chapter == controller.currentChapter;
    final isSelectedCh = (s.selectedBook != null && s.selectedChapter != null)
        ? (book == s.selectedBook && chapter == s.selectedChapter)
        : (book == controller.currentBook && chapter == controller.currentChapter);
    final bn = controller.bookNumber(book);
    final cid = bibleChapterId(bn, chapter);
    final crossRefs = s.loadedCrossRefs[cid]?[verse.number] ??
        (isCurrentCh ? (s.chapterCrossRefs[verse.number] ?? const []) : const []);
    final backgrounds = s.loadedBackgrounds[cid]?[verse.number] ??
        (isCurrentCh ? (s.chapterBackgrounds[verse.number] ?? const []) : const []);

    return VerseItem(
      verse: verse,
      isSelected: isSelectedCh && s.selectedVerses.contains(verse.number),
      isHighlighted: isCurrentCh && s.highlightedVerse == verse.number,
      highlightColorIndex: s.verseHighlights[highlightKey],
      hasNote: s.verseNotes.contains(highlightKey),
      appearance: controller.appearance,
      onVerseTap: () => onVerseTap(verse.number, book: book, chapter: chapter),
      crossReferences: crossRefs,
      backgroundNotes: backgrounds,
      resolvedTexts: isCurrentCh ? s.crossRefTexts : const {},
      selectedCount: isSelectedCh ? s.selectedVerses.length : 0,
      onCopy: onCopy,
      onShare: onShare,
      onBookmark: onBookmark,
      onClear: onClear,
      onOpenStudyPage: (initialTab) =>
          onOpenStudyPage(verse.number, initialTab: initialTab, book: book, chapter: chapter),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({
    super.key,
    required this.appearance,
  });

  final ReaderAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final fill = appearance.surfaceVariant(context.tokens);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.7,
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.45,
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPushManager});
  final VoidCallback onPushManager;

  @override
  Widget build(BuildContext context) {
    final dm = BibleDownloadManager();
    final isDownloading = dm.isDownloading(BibleDownloadManager.defaultVersionId);
    final indeterminate = dm.isIndeterminate(BibleDownloadManager.defaultVersionId);
    final progress = dm.getProgress(BibleDownloadManager.defaultVersionId);

    if (isDownloading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: indeterminate ? null : progress,
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Downloading the Tamil Bible (${BibleDownloadManager.defaultVersionId})…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                indeterminate ? 'Downloading…' : '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No Bibles installed yet.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Download one from the Bible Translations page.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onPushManager,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Manage Bibles'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterEmptyState extends StatelessWidget {
  const _ChapterEmptyState({
    required this.controller,
    required this.onRedownloadDefault,
  });

  final BibleController controller;
  final VoidCallback onRedownloadDefault;

  @override
  Widget build(BuildContext context) {
    final dm = BibleDownloadManager();
    if (dm.isDownloading(BibleDownloadManager.defaultVersionId)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Downloading Bible translation...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final bookLabel = controller.displayBookName(controller.currentBook);
    final chapterLabel = bookLabel.isNotEmpty
        ? '$bookLabel ${controller.currentChapter}'
        : controller.displayChapterTitle(controller.currentChapter);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No verses found for $chapterLabel.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'The offline copy of this translation may be incomplete.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRedownloadDefault,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Re-download Tamil Bible'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.chapter,
    required this.appearance,
    this.bookName,
    this.chapterTitle,
    this.isBookStart = false,
  });

  final int chapter;
  final ReaderAppearance appearance;
  final String? bookName;
  final String? chapterTitle;
  final bool isBookStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final hasBookName = bookName != null && bookName!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        top: isBookStart ? 20.0 : 32.0,
        bottom: 16.0,
        left: 16.0,
        right: 16.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBookStart && hasBookName) ...[
            Text(
              bookName!,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
          ],
          Text(
            chapterTitle ?? 'Chapter $chapter',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isBookStart
                  ? appearance.mutedTextColor(tokens)
                  : theme.colorScheme.primary,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 48,
            endIndent: 48,
            color: appearance.surfaceBorder(tokens).withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

