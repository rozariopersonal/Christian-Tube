import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../dictionary/widgets/inline_dictionary_popover.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../models/bible_verse.dart';
import '../services/bible_chapter_stream.dart';
import '../widgets/verse_item.dart';
import '../controllers/bible_controller.dart';

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
  final ValueChanged<int> onVerseTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final void Function(int verseNumber, {int initialTab}) onOpenStudyPage;
  final VoidCallback onPushManager;
  final VoidCallback onRedownloadDefault;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    if (s.isLoading) return const Center(child: CircularProgressIndicator());
    if (s.versions.isEmpty) return _EmptyState(onPushManager: onPushManager);
    if (s.chapterEmpty) {
      return _ChapterEmptyState(
        controller: controller,
        onRedownloadDefault: onRedownloadDefault,
      );
    }
    final verseIndex = s.index;
    final itemCount = s.totalRows;
    final isWholeBible = verseIndex != null;
    return MaxWidthBox(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            SystemChannels.textInput.invokeMethod('TextInput.hide');
            controller.clearSelection();
          }
          return false;
        },
        child: SelectionArea(
          contextMenuBuilder: (context, selectableRegionState) {
            String selectedText = '';
            try {
              final dynamic dyn = selectableRegionState;
              final dynamic content = dyn.getSelectedContent();
              if (content != null && content.plainText != null && (content.plainText as String).trim().isNotEmpty) {
                selectedText = (content.plainText as String).trim();
              }
            } catch (_) {}

            final words = selectedText
                .split(RegExp(r'\s+'))
                .map((w) => w.replaceAll(RegExp(r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]'''), ''))
                .where((w) => w.isNotEmpty)
                .toList();
            final lookupWord = words.isNotEmpty ? words.first : selectedText;

            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: selectableRegionState.contextMenuAnchors,
              buttonItems: [
                if (lookupWord.isNotEmpty)
                  ContextMenuButtonItem(
                    label: 'Define',
                    onPressed: () {
                      selectableRegionState.hideToolbar();
                      InlineDictionaryPopover.show(context, word: lookupWord);
                    },
                  ),
                ...selectableRegionState.contextMenuButtonItems,
              ],
            );
          },
          child: ScrollablePositionedList.builder(
            itemScrollController: itemScrollController,
            itemPositionsListener: itemPositionsListener,
            itemCount: itemCount,
            minCacheExtent: 300,
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemBuilder: (context, index) {
              if (index < 0 || index >= itemCount) return const SizedBox.shrink();
              if (!isWholeBible) {
                if (index >= s.verses.length) return const SizedBox.shrink();
                final verse = s.verses[index];
                final verseWidget = _VerseRow(
                  verse: verse,
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
                      SelectionContainer.disabled(
                        child: _ChapterHeader(
                          chapter: controller.currentChapter,
                          bookName: controller.displayBookName(controller.currentBook),
                          isBookStart: controller.currentChapter == 1,
                        ),
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
              if (rows == null || ref.verse > rows.length) {
                if (ref.verse == 1) {
                  final bookName = BookNameService.englishNameFor(ref.bookNumber);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectionContainer.disabled(
                        child: _ChapterHeader(
                          chapter: ref.chapter,
                          bookName: controller.displayBookName(bookName),
                          isBookStart: ref.chapter == 1,
                        ),
                      ),
                      _PlaceholderRow(
                        key: ValueKey('ph-${ref.bookNumber}-${ref.chapter}-${ref.verse}'),
                      ),
                    ],
                  );
                }
                return _PlaceholderRow(
                  key: ValueKey('ph-${ref.bookNumber}-${ref.chapter}-${ref.verse}'),
                );
              }
              final verseWidget = _VerseRow(
                verse: rows[ref.verse - 1],
                controller: controller,
                onVerseTap: onVerseTap,
                onCopy: onCopy,
                onShare: onShare,
                onBookmark: onBookmark,
                onClear: onClear,
                onOpenStudyPage: onOpenStudyPage,
              );
              if (ref.verse == 1) {
                final bookName = BookNameService.englishNameFor(ref.bookNumber);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectionContainer.disabled(
                      child: _ChapterHeader(
                        chapter: ref.chapter,
                        bookName: controller.displayBookName(bookName),
                        isBookStart: ref.chapter == 1,
                      ),
                    ),
                    verseWidget,
                  ],
                );
              }
              return verseWidget;
            },
          ),
        ),
      ),
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.verse,
    required this.controller,
    required this.onVerseTap,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    required this.onOpenStudyPage,
  });

  final BibleVerse verse;
  final BibleController controller;
  final ValueChanged<int> onVerseTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final void Function(int verseNumber, {int initialTab}) onOpenStudyPage;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    return VerseItem(
      verse: verse,
      isSelected: s.selectedVerses.contains(verse.number),
      isHighlighted: s.highlightedVerse == verse.number,
      appearance: controller.appearance,
      onVerseTap: () => onVerseTap(verse.number),
      crossReferences: s.chapterCrossRefs[verse.number] ?? const [],
      backgroundNotes: s.chapterBackgrounds[verse.number] ?? const [],
      resolvedTexts: s.crossRefTexts,
      selectedCount: s.selectedVerses.length,
      onCopy: onCopy,
      onShare: onShare,
      onBookmark: onBookmark,
      onClear: onClear,
      onOpenStudyPage: (initialTab) =>
          onOpenStudyPage(verse.number, initialTab: initialTab),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final fill = context.tokens.surfaceVariant;
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
      return const SizedBox.shrink();
    }
    final bookLabel = controller.displayBookName(controller.currentBook);
    final chapterLabel = bookLabel.isNotEmpty
        ? '$bookLabel ${controller.currentChapter}'
        : 'Chapter ${controller.currentChapter}';
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
    this.bookName,
    this.isBookStart = false,
  });

  final int chapter;
  final String? bookName;
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
            'Chapter $chapter',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isBookStart
                  ? tokens.onSurfaceMuted
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
            color: tokens.surfaceBorder.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

