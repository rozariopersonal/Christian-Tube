import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/features/books/services/book_reader_appearance.dart';

/// A single page column used in dual-page spread mode.
///
/// Renders the page's loading/error/content states plus a "Page N" footer. Owns
/// no state: content is sourced from [BookReaderController], and the scroll
/// progress tracking and fetch trigger are delegated through [controller] and
/// the page-aware [onTriggerFetch]/[onRetry] callbacks.
class ReaderPageColumn extends StatelessWidget {
  final int pageNum;
  final AppTokens tokens;
  final Color textColor;
  final bool isRightPage;
  final BookReaderController controller;
  final BookReaderAppearance appearance;
  final void Function(int pageNum) onTriggerFetch;
  final void Function(int pageNum) onRetry;
  final Widget Function(BuildContext context, SelectableRegionState state, int pageNum) buildSelectionToolbar;
  final Widget Function(BookRenderBlock block, int pageNum, Color textColor, AppTokens tokens) buildBlock;

  const ReaderPageColumn({
    super.key,
    required this.pageNum,
    required this.tokens,
    required this.textColor,
    required this.isRightPage,
    required this.controller,
    required this.appearance,
    required this.onTriggerFetch,
    required this.onRetry,
    required this.buildSelectionToolbar,
    required this.buildBlock,
  });

  @override
  Widget build(BuildContext context) {
    final lines = controller.pageCache(pageNum);
    final isLoading = controller.isPageLoading(pageNum);
    final hasFailed = controller.hasPageFailed(pageNum);

    if (hasFailed || (lines != null && lines.isEmpty && !isLoading)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, size: 36, color: tokens.onSurfaceMuted.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text(
                'Page $pageNum not available',
                style: TextStyle(color: tokens.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Unable to load page content',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                onPressed: () => onRetry(pageNum),
              ),
            ],
          ),
        ),
      );
    }

    if (lines == null || (lines.isEmpty && isLoading)) {
      if (!isLoading && !hasFailed) {
        onTriggerFetch(pageNum);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading page $pageNum...',
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final blocks = BookParagraphGrouper.groupLines(lines);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                final metrics = notification.metrics;
                if (metrics.maxScrollExtent > 0 && lines.isNotEmpty) {
                  final scrollFraction = (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);
                  final lineIndex = ((lines.length - 1) * scrollFraction).round();
                  final currentLine = lines[lineIndex].lineNumber;
                  final percent = controller.completionForLine(currentLine);
                  controller.markProgress(pageNum, currentLine, percent);
                }
              }
              return false;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SelectionArea(
                contextMenuBuilder: (context, state) => buildSelectionToolbar(context, state, pageNum),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: blocks.map((b) => buildBlock(b, pageNum, textColor, tokens)).toList(),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          alignment: isRightPage ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            'Page $pageNum',
            style: TextStyle(
              color: appearance.mutedTextColor(tokens),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
