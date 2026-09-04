import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/features/books/services/book_reader_appearance.dart';

/// The single-page horizontal swipe feed (used on `compact` screens).
///
/// Replaces the old infinite scroll view to provide a stable, standard paginated
/// reading experience using a `PageView`.
class MobilePageView extends StatefulWidget {
  final AppTokens tokens;
  final BookReaderController controller;
  final BookReaderAppearance appearance;
  final PageController pageController;
  final VoidCallback onToggleChrome;
  final void Function(int pageNum) onTriggerFetch;
  final void Function(int pageNum) onRetry;
  final Widget Function(BuildContext context, SelectableRegionState state, int pageNum) buildSelectionToolbar;
  final Widget Function(BookRenderBlock block, int pageNum, Color textColor, AppTokens tokens) buildBlock;
  final void Function(int pageNum) onPageChanged;

  const MobilePageView({
    super.key,
    required this.tokens,
    required this.controller,
    required this.appearance,
    required this.pageController,
    required this.onToggleChrome,
    required this.onTriggerFetch,
    required this.onRetry,
    required this.buildSelectionToolbar,
    required this.buildBlock,
    required this.onPageChanged,
  });

  @override
  State<MobilePageView> createState() => _MobilePageViewState();
}

class _MobilePageViewState extends State<MobilePageView> {
  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    final totalPages = s.book?.totalPages ?? 1;
    final textColor = widget.appearance.textColor(context.tokens);

    return GestureDetector(
      onTap: widget.onToggleChrome,
      behavior: HitTestBehavior.opaque,
      child: PageView.builder(
        controller: widget.pageController,
        onPageChanged: (index) {
          widget.onPageChanged(index + 1);
        },
        itemCount: totalPages,
        itemBuilder: (context, index) {
          final pageNum = index + 1;
          return _buildPageSection(pageNum, widget.tokens, textColor);
        },
      ),
    );
  }

  Widget _buildPageSection(int pageNum, AppTokens tokens, Color textColor) {
    final lines = widget.controller.pageCache(pageNum);
    final isLoading = widget.controller.isPageLoading(pageNum);
    final hasFailed = widget.controller.hasPageFailed(pageNum);

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
                onPressed: () => widget.onRetry(pageNum),
              ),
            ],
          ),
        ),
      );
    } else if (lines == null || (lines.isEmpty && isLoading)) {
      if (!isLoading && !hasFailed) {
        widget.onTriggerFetch(pageNum);
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
            ...blocks.map((b) => widget.buildBlock(b, pageNum, textColor, tokens)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 60),
      child: SelectionArea(
        contextMenuBuilder: (context, state) => widget.buildSelectionToolbar(context, state, pageNum),
        child: content,
      ),
    );
  }
}
