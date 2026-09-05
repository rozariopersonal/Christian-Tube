import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/services/book_line_index.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/features/books/services/scripture_ref_parser.dart';
import 'package:mobile/features/books/widgets/book_line_item.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// The continuous whole-book scroll body for the book reader.
///
/// Renders one [BookLine] per index of a fixed [totalLines]-long list, resolving
/// every row through [index]. Chapters that have not streamed yet render
/// fixed-height shimmer rows so the list extent never shifts while scrolling.
/// Positions are reported through [itemPositionsListener]; jump targets go
/// through [itemScrollController].
class BookVirtualScrollContent extends StatelessWidget {
  const BookVirtualScrollContent({
    super.key,
    required this.totalLines,
    required this.totalChapters,
    required this.index,
    required this.isChapterLoaded,
    required this.chapterLines,
    required this.highlightCache,
    required this.appearance,
    required this.tokens,
    required this.textColor,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.makeRecognizer,
    required this.onTriggerFetch,
    required this.buildSelectionToolbar,
  });

  final int totalLines;

  /// Canonical chapter count of the book (from its TOC); bounds probing of
  /// unknown chapters when a skeleton row asks for the next chapter.
  final int totalChapters;
  final BookLineIndex index;
  final bool Function(int chapterIndex) isChapterLoaded;
  final List<BookLine>? Function(int chapterIndex) chapterLines;
  final List<BookHighlight> Function(int pageNumber) highlightCache;
  final ReaderAppearance appearance;
  final AppTokens tokens;
  final Color textColor;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final TapGestureRecognizer Function(
      ParsedScriptureRef? parsed, String refText) makeRecognizer;
  final void Function(int chapterIndex) onTriggerFetch;
  final Widget Function(
      BuildContext context, SelectableRegionState selectableRegionState)
      buildSelectionToolbar;

  @override
  Widget build(BuildContext context) {
    if (totalLines <= 0) return const SizedBox.shrink();

    return SelectionArea(
      contextMenuBuilder: (context, state) =>
          buildSelectionToolbar(context, state),
      child: ScrollablePositionedList.builder(
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        itemCount: totalLines,
        minCacheExtent: 300,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        itemBuilder: (context, row) {
          if (row < 0 || row >= totalLines) return const SizedBox.shrink();
          return _buildItem(row);
        },
      ),
    );
  }

  Widget _buildItem(int row) {
    final split = index.splitRow(row);
    if (split == null) {
      final candidate = index.nextChapterAfterKnown;
      if (candidate != null &&
          candidate <= totalChapters &&
          !isChapterLoaded(candidate)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onTriggerFetch(candidate);
        });
      }
      return _lineSkeleton(row);
    }

    final lines = chapterLines(split.chapterIndex);
    if (lines == null || split.ordinal >= lines.length) {
      if (!isChapterLoaded(split.chapterIndex)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onTriggerFetch(split.chapterIndex);
        });
      }
      return _lineSkeleton(row);
    }

    final line = lines[split.ordinal];
    final next = split.ordinal + 1 < lines.length
        ? lines[split.ordinal + 1]
        : null;
    return BookLineItem(
      key: ValueKey('bl-${split.chapterIndex}-${split.ordinal}'),
      line: line,
      textColor: textColor,
      tokens: tokens,
      appearance: appearance,
      highlightCache: highlightCache(line.pageNumber),
      makeRecognizer: makeRecognizer,
      paragraphBreakAfter:
          BookParagraphGrouper.isParagraphBreakBetween(line, next),
    );
  }

  Widget _lineSkeleton(int row) {
    final estimatedHeight =
        appearance.fontSize * appearance.lineHeight + 10;
    return KeyedSubtree(
      key: ValueKey('ph-$row'),
      child: SizedBox(
        height: estimatedHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: FractionallySizedBox(
            widthFactor: row.isEven ? 1.0 : 0.72,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}