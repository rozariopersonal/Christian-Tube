import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';
import 'package:mobile/features/books/services/book_paragraph_grouper.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'reader_page_column.dart';

/// The two-page spread layout for `medium`/`expanded` screens.
///
/// Composes a left and right [ReaderPageColumn] with navigation chevrons and a
/// hairline divider. Pure presentational component; all behavior is forwarded
/// through callbacks and the shared [BookReaderController].
class DualPageSpreadView extends StatelessWidget {
  final AppTokens tokens;
  final BookReaderController controller;
  final ReaderAppearance appearance;
  final void Function(int delta) onTurnSpread;
  final VoidCallback onToggleChrome;
  final void Function(int pageNum) onTriggerFetch;
  final void Function(int pageNum) onRetry;
  final Widget Function(BuildContext context, SelectableRegionState state, int pageNum) buildSelectionToolbar;
  final Widget Function(BookRenderBlock block, int pageNum, Color textColor, AppTokens tokens) buildBlock;

  const DualPageSpreadView({
    super.key,
    required this.tokens,
    required this.controller,
    required this.appearance,
    required this.onTurnSpread,
    required this.onToggleChrome,
    required this.onTriggerFetch,
    required this.onRetry,
    required this.buildSelectionToolbar,
    required this.buildBlock,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = appearance.textColor(context.tokens);
    final s = controller.state;
    final totalPages = s.book?.totalPages ?? 1;
    final leftPage = s.spreadLeftPage;
    final rightPage = leftPage + 1 <= totalPages ? leftPage + 1 : null;

    return GestureDetector(
      onTap: onToggleChrome,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 36),
              color: leftPage > 1 ? tokens.onSurface : tokens.onSurfaceDisabled.withValues(alpha: 0.3),
              onPressed: leftPage > 1 ? () => onTurnSpread(-2) : null,
              tooltip: 'Previous pages',
            ),
            Expanded(
              child: ReaderPageColumn(
                pageNum: leftPage,
                tokens: tokens,
                textColor: textColor,
                isRightPage: false,
                controller: controller,
                appearance: appearance,
                onTriggerFetch: onTriggerFetch,
                onRetry: onRetry,
                buildSelectionToolbar: buildSelectionToolbar,
                buildBlock: buildBlock,
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              color: tokens.surfaceBorder.withValues(alpha: 0.6),
            ),
            Expanded(
              child: rightPage != null
                  ? ReaderPageColumn(
                      pageNum: rightPage,
                      tokens: tokens,
                      textColor: textColor,
                      isRightPage: true,
                      controller: controller,
                      appearance: appearance,
                      onTriggerFetch: onTriggerFetch,
                      onRetry: onRetry,
                      buildSelectionToolbar: buildSelectionToolbar,
                      buildBlock: buildBlock,
                    )
                  : Center(
                      child: Text(
                        'End of Book',
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 36),
              color: rightPage != null && rightPage < totalPages
                  ? tokens.onSurface
                  : tokens.onSurfaceDisabled.withValues(alpha: 0.3),
              onPressed: rightPage != null && rightPage < totalPages ? () => onTurnSpread(2) : null,
              tooltip: 'Next pages',
            ),
          ],
        ),
      ),
    );
  }
}
