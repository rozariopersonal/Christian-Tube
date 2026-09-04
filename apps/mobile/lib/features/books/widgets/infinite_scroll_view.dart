import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/features/books/services/book_reader_appearance.dart';

/// The single-page infinite scroll feed (used on `compact` screens).
///
/// Renders previous pages above and next pages below a centered anchor page in
/// one [CustomScrollView], letting the reader scroll fluidly between chapters.
/// Pure presentational component: scroll/center/page keys are provided by the
/// parent, and all data/behavior flows through [controller] and the callbacks.
class InfiniteScrollView extends StatelessWidget {
  final AppTokens tokens;
  final BookReaderController controller;
  final BookReaderAppearance appearance;
  final List<int> prevPages;
  final List<int> nextPages;
  final ScrollController scrollController;
  final Key centerKey;
  final GlobalKey Function(int pageNum) resolvePageKey;
  final VoidCallback onToggleChrome;
  final void Function(int pageNum) onTriggerFetch;
  final void Function(int pageNum) onRetry;
  final Widget Function(BuildContext context, SelectableRegionState state, int pageNum) buildSelectionToolbar;
  final Widget Function(BookRenderBlock block, int pageNum, Color textColor, AppTokens tokens) buildBlock;

  const InfiniteScrollView({
    super.key,
    required this.tokens,
    required this.controller,
    required this.appearance,
    required this.prevPages,
    required this.nextPages,
    required this.scrollController,
    required this.centerKey,
    required this.resolvePageKey,
    required this.onToggleChrome,
    required this.onTriggerFetch,
    required this.onRetry,
    required this.buildSelectionToolbar,
    required this.buildBlock,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = appearance.textColor(context.tokens);

    return GestureDetector(
      onTap: onToggleChrome,
      behavior: HitTestBehavior.opaque,
      child: SelectionArea(
        contextMenuBuilder: (context, state) => buildSelectionToolbar(context, state, controller.state.currentPage),
        child: CustomScrollView(
          controller: scrollController,
          center: centerKey,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildPageSection(prevPages[index], tokens, textColor),
                  childCount: prevPages.length,
                ),
              ),
            ),
            SliverPadding(
              key: centerKey,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildPageSection(nextPages[index], tokens, textColor),
                  childCount: nextPages.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageSection(int pageNum, AppTokens tokens, Color textColor) {
    final lines = controller.pageCache(pageNum);
    final isLoading = controller.isPageLoading(pageNum);
    final hasFailed = controller.hasPageFailed(pageNum);

    Widget content;

    if (hasFailed || (lines != null && lines.isEmpty && !isLoading)) {
      content = Container(
        key: const ValueKey('error'),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Center(
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
    } else if (lines == null || (lines.isEmpty && isLoading)) {
      if (!isLoading && !hasFailed) {
        onTriggerFetch(pageNum);
      }
      content = Container(
        key: const ValueKey('loading'),
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
          ),
        ),
      );
    } else {
      final blocks = BookParagraphGrouper.groupLines(lines);
      content = Container(
        key: const ValueKey('content'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pageNum > 1) const SizedBox(height: 16),
            ...blocks.map((b) => buildBlock(b, pageNum, textColor, tokens)),
          ],
        ),
      );
    }

    return KeyedSubtree(
      key: resolvePageKey(pageNum),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: content,
      ),
    );
  }
}
