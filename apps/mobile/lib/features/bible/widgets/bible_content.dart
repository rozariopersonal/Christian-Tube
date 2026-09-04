import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../../core/layout/content_width.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../models/bible_verse.dart';
import '../widgets/verse_item.dart';
import '../controllers/bible_controller.dart';

class BibleContent extends StatelessWidget {
  const BibleContent({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.verseKeys,
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
  final ScrollController scrollController;
  final Map<int, GlobalKey> verseKeys;
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
        child: ListView.builder(
          controller: scrollController,
          itemCount: s.verses.length,
          scrollCacheExtent: const ScrollCacheExtent.pixels(300),
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemBuilder: (context, index) {
            if (index < 0 || index >= s.verses.length) return const SizedBox.shrink();
            final verse = s.verses[index];
            return _VerseRow(
              verse: verse,
              controller: controller,
              verseKeys: verseKeys,
              onVerseTap: onVerseTap,
              onCopy: onCopy,
              onShare: onShare,
              onBookmark: onBookmark,
              onClear: onClear,
              onOpenStudyPage: onOpenStudyPage,
            );
          },
        ),
      ),
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.verse,
    required this.controller,
    required this.verseKeys,
    required this.onVerseTap,
    required this.onCopy,
    required this.onShare,
    required this.onBookmark,
    required this.onClear,
    required this.onOpenStudyPage,
  });

  final BibleVerse verse;
  final BibleController controller;
  final Map<int, GlobalKey> verseKeys;
  final ValueChanged<int> onVerseTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onBookmark;
  final VoidCallback onClear;
  final void Function(int verseNumber, {int initialTab}) onOpenStudyPage;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final Key? itemKey = verse.isChapterHeader
        ? null
        : (verseKeys[verse.number] ??= GlobalKey());
    return VerseItem(
      key: itemKey,
      verse: verse,
      isSelected: s.selectedVerses.contains(verse.number),
      isHighlighted: s.highlightedVerse == verse.number,
      fontSize: s.settings.fontSize,
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
